import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BalsuyuServisApp());
}

const String googleTabloWebhookUrl = String.fromEnvironment(
  'WEBHOOK_URL',
  defaultValue:
      'https://script.google.com/macros/s/AKfycbxW2SBjMD8KZ3NnjyMr_SdgHd1FEQyvsPMUBg4umDE51qRBAiiisa4lS2QURl3K86Y0/exec',
);

Future<Map<String, dynamic>> apiPost(Map<String, dynamic> paket) async {
  try {
    var res = await http
        .post(
          Uri.parse(googleTabloWebhookUrl),
          body: jsonEncode(paket),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode == 301 ||
        res.statusCode == 302 ||
        res.statusCode == 303 ||
        res.statusCode == 307 ||
        res.statusCode == 308) {
      final loc = res.headers['location'];
      if (loc != null && loc.isNotEmpty) {
        res = await http
            .get(Uri.parse(loc))
            .timeout(const Duration(seconds: 15));
      }
    }

    if (res.statusCode == 200) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        return {
          'basarili': false,
          'hata': 'Sunucu gecersiz yanit dondu. Web App dagitimini kontrol ediniz.',
        };
      }
    }
    return {'basarili': false, 'hata': 'Sunucu hatasi (${res.statusCode})'};
  } catch (_) {
    return {
      'basarili': false,
      'agHatasi': true,
      'hata': 'Baglanti hatasi. Internetinizi kontrol ediniz.',
    };
  }
}

Future<Map<String, dynamic>> apiGet(Map<String, String> params) async {
  try {
    final uri =
        Uri.parse(googleTabloWebhookUrl).replace(queryParameters: params);
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        return {
          'basarili': false,
          'hata': 'Sunucu gecersiz yanit dondu. Web App dagitimini kontrol ediniz.',
        };
      }
    }
    return {'basarili': false, 'hata': 'Sunucu hatasi (${res.statusCode})'};
  } catch (_) {
    return {
      'basarili': false,
      'agHatasi': true,
      'hata': 'Baglanti hatasi. Internetinizi kontrol ediniz.',
    };
  }
}

class OfflineKuyruk {
  static const String _key = 'balsuyu_offline_kuyruk';

  static Future<List<Map<String, dynamic>>> _oku() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> _yaz(List<Map<String, dynamic>> liste) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(liste));
  }

  static Future<int> sayi() async => (await _oku()).length;

  static Future<int> ekle(Map<String, dynamic> paket, String etiket) async {
    final trNow = DateTime.now().toUtc().add(const Duration(hours: 3));
    final saatStr =
        '${trNow.hour.toString().padLeft(2, '0')}:${trNow.minute.toString().padLeft(2, '0')}';
    final kopya = Map<String, dynamic>.from(paket);
    kopya['cevirimdisiSaat'] = kopya['cevirimdisiSaat'] ?? saatStr;
    final liste = await _oku();
    liste.add({'paket': kopya, 'etiket': etiket, 'saat': saatStr});
    await _yaz(liste);
    return liste.length;
  }

  static Future<Map<String, int>> gonder() async {
    final liste = await _oku();
    if (liste.isEmpty) return {'gonderilen': 0, 'kalan': 0};
    int gonderilen = 0;
    final List<Map<String, dynamic>> kalanlar = [];
    bool agKesildi = false;
    for (final item in liste) {
      if (agKesildi) {
        kalanlar.add(item);
        continue;
      }
      final paket = item['paket'];
      if (paket is! Map) continue;
      final res = await apiPost(Map<String, dynamic>.from(paket));
      if (res['agHatasi'] == true) {
        agKesildi = true;
        kalanlar.add(item);
      } else {
        if (res['basarili'] == true) gonderilen++;
      }
    }
    await _yaz(kalanlar);
    return {'gonderilen': gonderilen, 'kalan': kalanlar.length};
  }
}

int saatMetniDakikaya(dynamic saatStr, int varsayilan) {
  final s = (saatStr ?? '').toString().trim();
  final parcalar = s.split(':');
  if (parcalar.length == 2) {
    final h = int.tryParse(parcalar[0]);
    final d = int.tryParse(parcalar[1]);
    if (h != null && d != null && h >= 0 && h <= 23 && d >= 0 && d <= 59) {
      return h * 60 + d;
    }
  }
  return varsayilan;
}

Widget duyuruBandiWidget(Map<String, dynamic>? duyuru) {
  if (duyuru == null || (duyuru['metin'] ?? '').toString().trim().isEmpty) {
    return const SizedBox.shrink();
  }
  final acilMi = duyuru['onem'] == 'acil';
  final saat = (duyuru['saat'] ?? '').toString();
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: acilMi ? Colors.red.shade900.withAlpha(220) : Colors.blue.shade900.withAlpha(210),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: acilMi ? Colors.redAccent : Colors.lightBlueAccent),
    ),
    child: Row(
      children: [
        Icon(
          acilMi ? Icons.campaign_rounded : Icons.notifications_active_rounded,
          color: acilMi ? Colors.amberAccent : Colors.lightBlueAccent,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'DUYURU${saat.isNotEmpty ? ' ($saat)' : ''}: ${duyuru['metin']}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget soforUyariBandiWidget(Map<String, String> srvDurum) {
  final uyari = (srvDurum['soforUyarisi'] ?? '').trim();
  if (uyari.isEmpty) return const SizedBox.shrink();
  final arizaMi = (srvDurum['soforUyariTuru'] ?? '') == 'ARIZA';
  final saat = (srvDurum['soforUyariSaati'] ?? '').trim();
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: arizaMi ? Colors.red.shade900.withAlpha(210) : Colors.amber.shade900.withAlpha(210),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: arizaMi ? Colors.redAccent : Colors.amberAccent),
    ),
    child: Row(
      children: [
        Icon(
          arizaMi ? Icons.build_circle_rounded : Icons.schedule_rounded,
          color: Colors.white,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${arizaMi ? 'SERVİS ARIZA' : 'SERVİS GECİKME'}${saat.isNotEmpty ? ' ($saat)' : ''}: $uyari',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget kuyrukBandiWidget(int sayi, VoidCallback onGonder) {
  if (sayi <= 0) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.orange.shade900.withAlpha(220),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.amberAccent),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: Colors.amberAccent, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Çevrimdışı Kuyruk: $sayi kayıt bağlantı gelince otomatik gönderilecek.',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextButton(
          onPressed: onGonder,
          style: TextButton.styleFrom(
            foregroundColor: Colors.amberAccent,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(50, 24),
          ),
          child: const Text('Dene', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

String getBugununGunu() {
  const gunler = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  return gunler[DateTime.now().weekday - 1];
}

String normalizePlaka(String s) => s.replaceAll(' ', '').toUpperCase().trim();

String maskeleSoyad(String adSoyad) {
  final parcalar =
      adSoyad.trim().split(' ').where((e) => e.isNotEmpty).toList();
  if (parcalar.length <= 1) return adSoyad;
  final soyad = parcalar.last;
  final adlar = parcalar.sublist(0, parcalar.length - 1).join(' ');
  final ilk = soyad.isNotEmpty ? soyad[0].toUpperCase() : '';
  return '$adlar $ilk.';
}

Future<void> linkAc(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gecersiz baglanti.')),
      );
    }
    return;
  }
  try {
    final acildi = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!acildi && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Baglanti acilamadi.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Baglanti acilamadi.')),
      );
    }
  }
}

Future<void> telefonlaAra(BuildContext context, String tel) async {
  final cleanTel = tel.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleanTel.isEmpty || cleanTel == '-') {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon numarası kayıtlı değil.')),
      );
    }
    return;
  }
  final uri = Uri.parse('tel:$cleanTel');
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Arama başlatılamadı: $tel')),
      );
    }
  }
}

void akilliAramaPenceresi(
  BuildContext context,
  String adSoyad,
  String veliTel,
  String ogrenciTel,
) {
  final temizOgrTel = ogrenciTel.trim();
  if (temizOgrTel.isEmpty || temizOgrTel == '-' || temizOgrTel == 'null') {
    telefonlaAra(context, veliTel);
    return;
  }
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '$adSoyad İletişim',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kimi aramak istiyorsunuz?',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.phone_android_rounded),
            label: Text(
              'Öğrenciyi Ara ($temizOgrTel)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              telefonlaAra(context, temizOgrTel);
            },
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.family_restroom_rounded),
            label: Text(
              'Veliyi Ara ($veliTel)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              telefonlaAra(context, veliTel);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class NobetciOgretmen {
  final String gun;
  final String adSoyad;

  NobetciOgretmen({required this.gun, required this.adSoyad});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NobetciOgretmen &&
          other.gun == gun &&
          other.adSoyad == adSoyad);

  @override
  int get hashCode => gun.hashCode ^ adSoyad.hashCode;
}

class Ogrenci {
  final String id;
  final String adSoyad;
  final String sinif;
  final String koyDurak;
  final String plaka;
  final String veliTel;
  final String ogrenciTel;
  String durum;
  int adim;
  String saat;
  String izinli;

  Ogrenci({
    required this.id,
    required this.adSoyad,
    required this.sinif,
    required this.koyDurak,
    required this.plaka,
    required this.veliTel,
    this.ogrenciTel = '',
    this.durum = 'binmedi',
    this.adim = 0,
    this.saat = '',
    this.izinli = '',
  });

  factory Ogrenci.fromJson(Map<String, dynamic> item) {
    return Ogrenci(
      id: (item['okulNo'] ?? '').toString().trim(),
      adSoyad: (item['adSoyad'] ?? '').toString().trim(),
      sinif: (item['sinif'] ?? '').toString().trim(),
      koyDurak: (item['koyDurak'] ?? '').toString().trim(),
      plaka: (item['plaka'] ?? '').toString().trim(),
      veliTel: item['veliTel'] != null ? item['veliTel'].toString().trim() : '-',
      ogrenciTel:
          item['ogrenciTel'] != null ? item['ogrenciTel'].toString().trim() : '',
      durum: (item['durum'] != null && item['durum'].toString().isNotEmpty)
          ? item['durum'].toString().trim()
          : 'binmedi',
      adim: item['adim'] != null ? int.tryParse(item['adim'].toString()) ?? 0 : 0,
      saat: item['saat'] != null ? item['saat'].toString().trim() : '',
      izinli: item['izinli'] != null ? item['izinli'].toString().trim() : '',
    );
  }
}

class ServisHatti {
  final String plaka;
  final String hatAdi;
  final String guzergah;
  final String soforAdi;
  final String soforTel;
  final List<Ogrenci> ogrenciler;

  ServisHatti({
    required this.plaka,
    required this.hatAdi,
    required this.guzergah,
    required this.soforAdi,
    required this.soforTel,
    required this.ogrenciler,
  });
}

List<Ogrenci> ogrencileriCoz(dynamic ham) {
  final List<Ogrenci> liste = [];
  if (ham is List) {
    for (final item in ham) {
      if (item is Map<String, dynamic>) {
        liste.add(Ogrenci.fromJson(item));
      }
    }
  }
  return liste;
}

List<ServisHatti> servisleriCoz(dynamic ham, List<Ogrenci> tumOgrenciler) {
  final List<ServisHatti> liste = [];
  if (ham is List) {
    for (final item in ham) {
      if (item is Map<String, dynamic>) {
        final plaka = (item['plaka'] ?? '').toString().trim();
        final ogrList = tumOgrenciler
            .where((o) => normalizePlaka(o.plaka) == normalizePlaka(plaka))
            .toList();
        liste.add(
          ServisHatti(
            plaka: plaka,
            hatAdi: (item['hatAdi'] ?? '').toString().trim(),
            guzergah: (item['guzergah'] ?? '').toString().trim(),
            soforAdi: (item['soforAdi'] ?? '').toString().trim(),
            soforTel: (item['soforTel'] ?? '').toString().trim(),
            ogrenciler: ogrList,
          ),
        );
      }
    }
  }
  return liste;
}

List<NobetciOgretmen> nobetcileriCoz(dynamic ham) {
  final List<NobetciOgretmen> liste = [];
  if (ham is List) {
    for (final item in ham) {
      if (item is Map<String, dynamic>) {
        liste.add(
          NobetciOgretmen(
            gun: (item['gun'] ?? '').toString().trim(),
            adSoyad: (item['ogretmen'] ?? '').toString().trim(),
          ),
        );
      }
    }
  }
  return liste;
}

String aktifNobetciAdiniCoz(Map<String, dynamic> veri) {
  final n = veri['aktifNobetci'];
  if (n is Map &&
      n['ogretmen'] != null &&
      n['ogretmen'].toString().trim().isNotEmpty) {
    return n['ogretmen'].toString().trim();
  }
  return 'Öğretmen';
}

String adimKisaEtiket(Ogrenci ogr) {
  if (ogr.izinli == 'TUM_GUN') return '📋 İZİNLİ (Tüm Gün)';
  if (ogr.izinli == 'SABAH' && ogr.adim < 2) return '📋 İZİNLİ (Sabah)';
  if (ogr.izinli == 'AKSAM' && ogr.adim >= 2 && ogr.adim < 4) {
    return '📋 İZİNLİ (Akşam)';
  }
  final s = ogr.saat.isNotEmpty ? ' (${ogr.saat})' : '';
  if (ogr.adim == 1) return '1. Sabah Bindi$s';
  if (ogr.adim == 2) return '2. Okulda İndi$s';
  if (ogr.adim == 3) return '3. Akşam Bindi$s';
  if (ogr.adim >= 4) return '4. Köyde İndi$s';
  return 'Henüz Binmedi';
}

class BalsuyuServisApp extends StatelessWidget {
  const BalsuyuServisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Balsuyu MTAL - Arslanoğlu Group',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A2E26)),
        useMaterial3: true,
      ),
      home: const AnaGecisEkrani(),
    );
  }
}

class AnaGecisEkrani extends StatefulWidget {
  const AnaGecisEkrani({super.key});

  @override
  State<AnaGecisEkrani> createState() => _AnaGecisEkraniState();
}

class _AnaGecisEkraniState extends State<AnaGecisEkrani> {
  int aktifSayfa = 0;

  final List<Widget> sayfalar = const [
    OgrenciNfcEkrani(),
    VeliPaneli(),
    SoforPaneli(),
    OgretmenPaneli(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: aktifSayfa, children: sayfalar),
      bottomNavigationBar: NavigationBar(
        selectedIndex: aktifSayfa,
        height: 62,
        backgroundColor: Colors.white,
        elevation: 4,
        onDestinationSelected: (index) => setState(() => aktifSayfa = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.nfc_outlined),
            selectedIcon: Icon(Icons.nfc, color: Color(0xFF0A2E26)),
            label: 'Öğrenci NFC',
          ),
          NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined),
            selectedIcon: Icon(Icons.family_restroom, color: Color(0xFF0A2E26)),
            label: 'Veli Takip',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_bus_outlined),
            selectedIcon: Icon(Icons.directions_bus, color: Color(0xFF0A2E26)),
            label: 'Şoför Paneli',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon:
                Icon(Icons.admin_panel_settings, color: Color(0xFF0A2E26)),
            label: 'Öğretmen',
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 1. ÖĞRENCİ NFC EKRANI
// ===========================================================================
class OgrenciNfcEkrani extends StatefulWidget {
  const OgrenciNfcEkrani({super.key});

  @override
  State<OgrenciNfcEkrani> createState() => _OgrenciNfcEkraniState();
}

class _OgrenciNfcEkraniState extends State<OgrenciNfcEkrani> {
  String? token;
  Ogrenci? girisYapanOgrenci;
  ServisHatti? ogrenciServisi;
  Map<String, String> servisDurumu = {};
  Map<String, dynamic> saatAyarlari = {};
  Map<String, dynamic>? duyuru;
  int kuyrukSayisi = 0;
  String aktifNobetciAd = 'Öğretmen';
  bool yukleniyor = false;
  bool islemYapiliyor = false;
  String sonIslemDurumu = 'bekliyor';
  String islemSaati = '';
  Timer? otoYenileyici;

  final TextEditingController noController = TextEditingController();
  final TextEditingController sifreController = TextEditingController();

  @override
  void initState() {
    super.initState();
    kayitliOturumuYukle();
    _kuyruguKontrolEt(sessiz: true);
    otoYenileyici = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      if (girisYapanOgrenci != null) {
        setState(() {});
      }
      if (token != null &&
          girisYapanOgrenci != null &&
          !yukleniyor &&
          !islemYapiliyor) {
        _kuyruguKontrolEt(sessiz: true);
        veriyiYenile(sessiz: true);
      }
    });
  }

  Future<void> _kuyruguKontrolEt({bool sessiz = false}) async {
    final s = await OfflineKuyruk.sayi();
    if (mounted && s != kuyrukSayisi) setState(() => kuyrukSayisi = s);
    if (s <= 0) return;
    final sonuc = await OfflineKuyruk.gonder();
    if (!mounted) return;
    setState(() => kuyrukSayisi = sonuc['kalan'] ?? 0);
    if ((sonuc['gonderilen'] ?? 0) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal.shade800,
          content: Text(
            '✅ Bekleyen ${sonuc['gonderilen']} çevrimdışı kayıt buluta gönderildi!',
          ),
        ),
      );
      veriyiYenile(sessiz: true);
    } else if (!sessiz && (sonuc['kalan'] ?? 0) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('İnternet henüz yok, kayıtlar cihazda güvende bekliyor.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    otoYenileyici?.cancel();
    noController.dispose();
    sifreController.dispose();
    super.dispose();
  }

  void veriyiUygula(Map<String, dynamic> veri) {
    final ogrList = ogrencileriCoz(veri['ogrenciler']);
    final srvList = servisleriCoz(veri['servisler'], ogrList);
    final rawSrvDurum = veri['servisDurumu'];
    final Map<String, String> yeniSrvDurum = {};
    if (rawSrvDurum is Map) {
      rawSrvDurum.forEach((k, v) {
        yeniSrvDurum[k.toString()] = (v ?? '').toString();
      });
    }
    final rawSaat = veri['saatAyarlari'];
    final rawDuyuru = veri['duyuru'];
    setState(() {
      girisYapanOgrenci = ogrList.isNotEmpty ? ogrList.first : null;
      ogrenciServisi = srvList.isNotEmpty ? srvList.first : null;
      servisDurumu = yeniSrvDurum;
      if (rawSaat is Map) saatAyarlari = Map<String, dynamic>.from(rawSaat);
      duyuru = rawDuyuru is Map ? Map<String, dynamic>.from(rawDuyuru) : null;
      aktifNobetciAd = aktifNobetciAdiniCoz(veri);
    });
  }

  Future<void> kayitliOturumuYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitliNo = prefs.getString('balsuyu_ogr_no');
    if (kayitliNo != null && mounted) noController.text = kayitliNo;
    final kayitliTok = prefs.getString('balsuyu_ogr_token');
    if (kayitliTok == null || kayitliTok.isEmpty) return;

    if (mounted) setState(() => yukleniyor = true);
    final res = await apiGet({'islem': 'durum_getir', 'token': kayitliTok});
    if (!mounted) return;
    if (res['basarili'] == true) {
      token = kayitliTok;
      veriyiUygula(res);
    } else if (res['yetkisiz'] == true) {
      await prefs.remove('balsuyu_ogr_token');
    }
    if (mounted) setState(() => yukleniyor = false);
  }

  Future<void> veriyiYenile({bool sessiz = false}) async {
    if (token == null) return;
    if (!sessiz && mounted) setState(() => yukleniyor = true);
    final res = await apiGet({'islem': 'durum_getir', 'token': token!});
    if (!mounted) return;
    if (res['basarili'] == true) {
      veriyiUygula(res);
    } else if (res['yetkisiz'] == true) {
      await ogrenciCikisYap();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Oturum süresi doldu, lütfen tekrar giriş yapınız.'),
          ),
        );
      }
    } else if (!sessiz) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'Veriler yenilenemedi.').toString()),
        ),
      );
    }
    if (!sessiz && mounted) setState(() => yukleniyor = false);
  }

  Future<void> ogrenciGirisYap() async {
    final girilenNo = noController.text.trim();
    final girilenSifre = sifreController.text.trim();
    if (girilenNo.isEmpty || girilenSifre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Okul numarası ve şifre boş bırakılamaz.'),
        ),
      );
      return;
    }

    setState(() => yukleniyor = true);
    final res = await apiPost({
      'islem': 'GIRIS_YAP',
      'rol': 'ogrenci',
      'okulNo': girilenNo,
      'sifre': girilenSifre,
    });
    if (!mounted) return;
    setState(() => yukleniyor = false);

    if (res['basarili'] == true &&
        res['token'] != null &&
        res['veri'] is Map<String, dynamic>) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_ogr_token', res['token'].toString());
      await prefs.setString('balsuyu_ogr_no', girilenNo);
      token = res['token'].toString();
      sifreController.clear();
      veriyiUygula(res['veri'] as Map<String, dynamic>);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text((res['hata'] ?? 'Giriş başarısız.').toString()),
        ),
      );
    }
  }

  Future<void> ogrenciCikisYap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('balsuyu_ogr_token');
    if (!mounted) return;
    setState(() {
      token = null;
      girisYapanOgrenci = null;
      ogrenciServisi = null;
      servisDurumu = {};
    });
  }

  void acilDurumPenceresiAc() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.redAccent, size: 28),
                SizedBox(width: 8),
                Text(
                  'ACİL DURUM MERKEZİ',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Lütfen durumunuza uygun butona basınız.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: const Icon(Icons.phone_in_talk, size: 22),
              label: const Text(
                '112 ACİL ÇAĞRI MERKEZİNİ ARA (Polis / Ambulans)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                telefonlaAra(context, '112');
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: const Icon(Icons.notifications_active_rounded, size: 22),
              label: const Text(
                'OKUL YÖNETİMİNE ACİL DURUM BİLDİR',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                yonetimeAcilBildir();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> yonetimeAcilBildir() async {
    if (girisYapanOgrenci == null || token == null) return;
    final res = await apiPost({
      'token': token,
      'okulNo': girisYapanOgrenci!.id,
      'plaka': girisYapanOgrenci!.plaka,
      'koy': girisYapanOgrenci!.koyDurak,
      'adSoyad': girisYapanOgrenci!.adSoyad,
      'sinif': girisYapanOgrenci!.sinif,
      'islem': 'ACİL_DURUM',
      'yontem': 'Öğrenci SOS',
      'ogretmen': aktifNobetciAd,
    });
    if (!mounted) return;
    if (res['basarili'] == true) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'İhbar İletildi',
            style: TextStyle(color: Colors.greenAccent, fontSize: 16),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Acil durum çağrınız Okul Yönetimine iletildi.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              SizedBox(height: 10),
              Text(
                'Lütfen sakin olun, araçtan ayrılmayın. Yönetim sizinle derhal iletişime geçecektir.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text(
                'ANLADIM',
                style: TextStyle(color: Colors.tealAccent),
              ),
            ),
          ],
        ),
      );
    } else if (res['yetkisiz'] == true) {
      await ogrenciCikisYap();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text(
              'Oturum süresi doldu, tekrar giriş yapınız veya acilse 112 arayınız!',
            ),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text(
            'İhbar gönderilemedi: ${(res['hata'] ?? 'İnternet yok').toString()} - Acilse 112 arayınız!',
          ),
        ),
      );
    }
  }

  Map<String, dynamic> _zamanDurumu(int adim) {
    final trSimdi = DateTime.now().toUtc().add(const Duration(hours: 3));
    final gun = trSimdi.weekday;
    final topDak = trSimdi.hour * 60 + trSimdi.minute;

    final sbBasStr = (saatAyarlari['sabahBinisBas'] ?? '06:30').toString();
    final sbBitStr = (saatAyarlari['sabahBinisBit'] ?? '07:30').toString();
    final siBasStr = (saatAyarlari['sabahInisBas'] ?? '07:30').toString();
    final siBitStr = (saatAyarlari['sabahInisBit'] ?? '08:00').toString();
    final pztAkStr = (saatAyarlari['pztAksamBas'] ?? '17:00').toString();
    final digAkStr = (saatAyarlari['digerAksamBas'] ?? '15:00').toString();
    final akBitStr = (saatAyarlari['aksamBit'] ?? '18:00').toString();
    final haftaSonuKapali = saatAyarlari['haftaSonuKapali'] != false;

    final sbBas = saatMetniDakikaya(sbBasStr, 390);
    final sbBit = saatMetniDakikaya(sbBitStr, 450);
    final siBas = saatMetniDakikaya(siBasStr, 450);
    final siBit = saatMetniDakikaya(siBitStr, 480);
    final aksamBasStr = gun == DateTime.monday ? pztAkStr : digAkStr;
    final aksamBas = saatMetniDakikaya(
      aksamBasStr,
      gun == DateTime.monday ? 17 * 60 : 15 * 60,
    );
    final akBit = saatMetniDakikaya(akBitStr, 1080);

    final izinli = girisYapanOgrenci?.izinli ?? '';
    if (izinli == 'TUM_GUN') {
      return {
        'binisAcik': false,
        'inisAcik': false,
        'kapaliMi': true,
        'baslik': 'Bugün İzinlisiniz',
        'aciklama':
            'Okul idaresi tarafından bugün için izinli (servise binmeyecek) olarak işaretlendiniz.',
      };
    }

    if (adim >= 4) {
      return {
        'binisAcik': false,
        'inisAcik': false,
        'kapaliMi': false,
        'baslik': 'Günlük İşlemler Tamam',
        'aciklama': 'Bugünkü tüm servis adımları tamamlandı.',
      };
    }

    if (haftaSonuKapali &&
        (gun == DateTime.saturday || gun == DateTime.sunday)) {
      return {
        'binisAcik': false,
        'inisAcik': false,
        'kapaliMi': true,
        'baslik': 'Hafta Sonu Kapalı',
        'aciklama':
            'Cumartesi ve Pazar günleri sistem kapalıdır. Pazartesi $sbBasStr\'da açılacaktır.',
      };
    }

    if (topDak < sbBas) {
      return {
        'binisAcik': false,
        'inisAcik': false,
        'kapaliMi': true,
        'baslik': 'Sistem Kapalı',
        'aciklama':
            'Sabah Biniş $sbBasStr - $sbBitStr saatleri arasında açılacaktır.',
      };
    }

    if (topDak >= sbBas && topDak < sbBit) {
      if (izinli == 'SABAH') {
        return {
          'binisAcik': false,
          'inisAcik': false,
          'kapaliMi': true,
          'baslik': 'Sabah İzinlisiniz',
          'aciklama':
              'Sabah servisi için idare tarafından izinli işaretlendiniz. Akşam $aksamBasStr\'da açılacaktır.',
        };
      }
      if (adim == 0) {
        return {
          'binisAcik': true,
          'inisAcik': false,
          'kapaliMi': false,
          'baslik': 'Sabah Biniş Aktif',
          'aciklama': '1. Sabah Köyden Biniş ($sbBasStr - $sbBitStr)',
          'binisMesaj': 'SABAH BİNDİ',
          'binisYeniAdim': 1,
        };
      }
      if (adim == 1) {
        return {
          'binisAcik': false,
          'inisAcik': false,
          'kapaliMi': true,
          'baslik': 'Sabah İniş Bekleniyor',
          'aciklama':
              'Sabah İndim butonu $siBasStr\'da açılacaktır ($siBasStr - $siBitStr).',
        };
      }
      return {
        'binisAcik': false,
        'inisAcik': false,
        'kapaliMi': true,
        'baslik': 'Akşam Bekleniyor',
        'aciklama': 'Akşam Biniş bugün $aksamBasStr\'da açılacaktır.',
      };
    }

    if (topDak >= siBas && topDak < siBit) {
      if (izinli == 'SABAH') {
        return {
          'binisAcik': false,
          'inisAcik': false,
          'kapaliMi': true,
          'baslik': 'Sabah İzinlisiniz',
          'aciklama':
              'Sabah servisi için izinlisiniz. Akşam Biniş bugün $aksamBasStr\'da açılacaktır.',
        };
      }
      final sabahTamamSaat = (servisDurumu['sabahTamam'] ?? '').trim();
      final bool sabahIndirmeBitti = sabahTamamSaat.isNotEmpty;
      if (adim <= 1 && !sabahIndirmeBitti) {
        return {
          'binisAcik': false,
          'inisAcik': true,
          'kapaliMi': false,
          'baslik': 'Sabah İniş Aktif',
          'aciklama': '2. Sabah Okula İniş ($siBasStr - $siBitStr)',
          'inisMesaj': 'SABAH İNDİ',
          'inisYeniAdim': 2,
        };
      }
      final saatBilgi = (girisYapanOgrenci?.saat.isNotEmpty == true)
          ? ' (${girisYapanOgrenci!.saat})'
          : (sabahIndirmeBitti ? ' ($sabahTamamSaat)' : '');
      return {
        'binisAcik': false,
        'inisAcik': false,
        'kapaliMi': true,
        'baslik': 'Okula İniş Onaylandı',
        'aciklama':
            'Sabah okula inişiniz kaydedildi$saatBilgi. Akşam Biniş bugün $aksamBasStr\'da açılacaktır.',
      };
    }

    if (topDak >= siBit && topDak < aksamBas) {
      return {
        'binisAcik': false,
        'inisAcik': false,
        'kapaliMi': true,
        'baslik': 'Sistem Kapalı',
        'aciklama':
            'Sistem $siBitStr\'da kapandı. Akşam Biniş bugün $aksamBasStr\'da açılacaktır.',
      };
    }

    if (topDak >= aksamBas && topDak < akBit) {
      if (izinli == 'AKSAM') {
        return {
          'binisAcik': false,
          'inisAcik': false,
          'kapaliMi': true,
          'baslik': 'Akşam İzinlisiniz',
          'aciklama':
              'Akşam servisi için okul idaresi tarafından izinli işaretlendiniz.',
        };
      }
      if (adim <= 2) {
        return {
          'binisAcik': true,
          'inisAcik': false,
          'kapaliMi': false,
          'baslik': 'Akşam Biniş Aktif',
          'aciklama': '3. Akşam Okuldan Biniş ($aksamBasStr - $akBitStr)',
          'binisMesaj': 'AKŞAM BİNDİ',
          'binisYeniAdim': 3,
        };
      }
      return {
        'binisAcik': false,
        'inisAcik': true,
        'kapaliMi': false,
        'baslik': 'Akşam İniş Aktif',
        'aciklama': '4. Akşam Köyde İniş ($akBitStr\'a kadar)',
        'inisMesaj': 'AKŞAM İNDİ',
        'inisYeniAdim': 4,
      };
    }

    return {
      'binisAcik': false,
      'inisAcik': false,
      'kapaliMi': true,
      'baslik': 'Sistem Kapandı',
      'aciklama':
          'Sistem $akBitStr itibarıyla tamamen kapandı. Bir sonraki okul günü $sbBasStr\'da açılacaktır.',
    };
  }

  Future<void> nfcIslemYap(String islemTuru) async {
    if (girisYapanOgrenci == null || token == null || islemYapiliyor) return;
    final adim = girisYapanOgrenci!.adim;
    if (adim >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.teal,
          content: Text('Bugünkü tüm servis işlemleriniz tamamlandı.'),
        ),
      );
      return;
    }

    final zaman = _zamanDurumu(adim);
    String tabloyaGidecekMesaj = '';
    String yeniDurum = '';
    int hedefAdim = adim + 1;

    if (islemTuru == 'bindi') {
      if (zaman['binisAcik'] == true) {
        tabloyaGidecekMesaj = (zaman['binisMesaj'] ?? 'SABAH BİNDİ').toString();
        yeniDurum = 'serviste';
        hedefAdim = (zaman['binisYeniAdim'] as int?) ?? (adim + 1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange.shade900,
            content: Text((zaman['aciklama'] ?? 'Biniş şu an kapalıdır.').toString()),
          ),
        );
        return;
      }
    } else {
      if (zaman['inisAcik'] == true) {
        tabloyaGidecekMesaj = (zaman['inisMesaj'] ?? 'SABAH İNDİ').toString();
        yeniDurum = 'indi';
        hedefAdim = (zaman['inisYeniAdim'] as int?) ?? (adim + 1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange.shade900,
            content: Text((zaman['aciklama'] ?? 'İniş şu an kapalıdır.').toString()),
          ),
        );
        return;
      }
    }

    final paket = {
      'token': token,
      'okulNo': girisYapanOgrenci!.id,
      'plaka': girisYapanOgrenci!.plaka,
      'koy': girisYapanOgrenci!.koyDurak,
      'adSoyad': girisYapanOgrenci!.adSoyad,
      'sinif': girisYapanOgrenci!.sinif,
      'islem': tabloyaGidecekMesaj,
      'yontem': 'NFC (Öğrenci)',
      'ogretmen': aktifNobetciAd,
    };

    setState(() => islemYapiliyor = true);
    final res = await apiPost(paket);
    if (!mounted) return;
    setState(() => islemYapiliyor = false);

    if (res['basarili'] == true) {
      final now = DateTime.now().toUtc().add(const Duration(hours: 3));
      final saatFormat =
          (res['saat'] != null && res['saat'].toString().isNotEmpty)
              ? res['saat'].toString()
              : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      setState(() {
        girisYapanOgrenci!.adim = hedefAdim;
        girisYapanOgrenci!.durum = yeniDurum;
        girisYapanOgrenci!.saat = saatFormat;
        sonIslemDurumu = islemTuru;
        islemSaati = saatFormat;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal.shade800,
          content: Text('$tabloyaGidecekMesaj kaydedildi!'),
        ),
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => sonIslemDurumu = 'bekliyor');
      });
    } else if (res['agHatasi'] == true) {
      final yeniSayi = await OfflineKuyruk.ekle(paket, tabloyaGidecekMesaj);
      final trNow = DateTime.now().toUtc().add(const Duration(hours: 3));
      final saatFormat =
          '${trNow.hour.toString().padLeft(2, '0')}:${trNow.minute.toString().padLeft(2, '0')}';
      if (!mounted) return;
      setState(() {
        kuyrukSayisi = yeniSayi;
        girisYapanOgrenci!.adim = hedefAdim;
        girisYapanOgrenci!.durum = yeniDurum;
        girisYapanOgrenci!.saat = saatFormat;
        sonIslemDurumu = islemTuru;
        islemSaati = saatFormat;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade900,
          content: Text(
            '📡 İnternet yok! $tabloyaGidecekMesaj ($saatFormat) cihazda saklandı, bağlantı gelince otomatik gönderilecek.',
          ),
        ),
      );
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => sonIslemDurumu = 'bekliyor');
      });
    } else if (res['yetkisiz'] == true) {
      await ogrenciCikisYap();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Oturum süresi doldu, lütfen tekrar giriş yapınız.'),
          ),
        );
      }
    } else {
      if (res['yenile'] == true) {
        veriyiYenile(sessiz: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'Kayıt gönderilemedi.').toString()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (girisYapanOgrenci == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  mebLogoRozeti(),
                  const SizedBox(height: 16),
                  const Text(
                    'BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Öğrenci Güvenli Girişi',
                    style: TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.teal.withAlpha(77)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Okul Numaranız:',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: noController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Örn: 482',
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Giriş Şifreniz (T.C. Son 4 Hanesi):',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: sifreController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: '••••',
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 46),
                          ),
                          icon: yukleniyor
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(
                            yukleniyor
                                ? 'Doğrulanıyor...'
                                : 'Cihazı Eşleştir ve Giriş Yap',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: yukleniyor ? null : ogrenciGirisYap,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  arslanogluGroupFooter(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final soforAdi = ogrenciServisi?.soforAdi ?? 'Bilinmiyor';
    final soforTel = ogrenciServisi?.soforTel ?? '-';
    final adim = girisYapanOgrenci!.adim;
    final zaman = _zamanDurumu(adim);
    final bool kapaliMi = zaman['kapaliMi'] == true;
    final bool binisAktif = !islemYapiliyor && zaman['binisAcik'] == true;
    final bool inisAktif = !islemYapiliyor && zaman['inisAcik'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
              child: Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade900.withAlpha(90),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.withAlpha(77)),
                    ),
                    child: Row(
                      children: [
                        mebLogoRozeti(),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              Text(
                                'Nöbetçi: $aktifNobetciAd',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.tealAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh,
                              color: Colors.tealAccent, size: 18),
                          tooltip: 'Yenile',
                          onPressed: yukleniyor ? null : () => veriyiYenile(),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: const Size(48, 30),
                          ),
                          onPressed: acilDurumPenceresiAc,
                          child: const Text(
                            'SOS',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout,
                              color: Colors.white60, size: 18),
                          tooltip: 'Çıkış Yap',
                          onPressed: ogrenciCikisYap,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  duyuruBandiWidget(duyuru),
                  soforUyariBandiWidget(servisDurumu),
                  kuyrukBandiWidget(kuyrukSayisi, () => _kuyruguKontrolEt()),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.withAlpha(55)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.teal.shade700,
                          child: const Icon(Icons.person,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                girisYapanOgrenci!.adSoyad,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'No: ${girisYapanOgrenci!.id} | Sınıf: ${girisYapanOgrenci!.sinif} | Durak: ${girisYapanOgrenci!.koyDurak}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            girisYapanOgrenci!.plaka,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF162032),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_in_talk_rounded,
                            color: Colors.tealAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Şoför: $soforAdi',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70),
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                          icon: const Icon(Icons.call, size: 12),
                          label: const Text(
                            'Şoförü Ara',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => telefonlaAra(context, soforTel),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (sonIslemDurumu == 'bekliyor') ...[
              Container(
                width: 136,
                height: 136,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (kapaliMi ? Colors.orange : Colors.teal).withAlpha(24),
                  border: Border.all(
                    color:
                        (kapaliMi ? Colors.orange : Colors.teal).withAlpha(110),
                    width: 3,
                  ),
                ),
                child: Center(
                  child: islemYapiliyor
                      ? const CircularProgressIndicator(
                          color: Colors.tealAccent)
                      : Icon(
                          adim >= 4
                              ? Icons.verified_rounded
                              : (kapaliMi
                                  ? Icons.lock_clock_rounded
                                  : Icons.nfc_rounded),
                          size: 68,
                          color: kapaliMi
                              ? Colors.orangeAccent
                              : Colors.tealAccent,
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                (zaman['baslik'] ?? 'NFC Okuyucu').toString(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: kapaliMi ? Colors.orangeAccent : Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  (zaman['aciklama'] ?? '').toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: kapaliMi ? Colors.amber.shade200 : Colors.tealAccent,
                  ),
                ),
              ),
            ] else ...[
              Icon(
                Icons.check_circle,
                size: 75,
                color: sonIslemDurumu == 'bindi'
                    ? Colors.greenAccent
                    : Colors.blueAccent,
              ),
              const SizedBox(height: 12),
              Text(
                sonIslemDurumu == 'bindi'
                    ? 'Biniş Kaydedildi!'
                    : 'İniş Kaydedildi!',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Saat: $islemSaati',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: binisAktif
                            ? Colors.green.shade800
                            : Colors.grey.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: const Icon(Icons.touch_app, size: 16),
                      label: const Text('Bindim (NFC)'),
                      onPressed:
                          binisAktif ? () => nfcIslemYap('bindi') : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: inisAktif
                            ? Colors.blue.shade800
                            : Colors.grey.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: const Icon(Icons.touch_app, size: 16),
                      label: const Text('İndim (NFC)'),
                      onPressed: inisAktif ? () => nfcIslemYap('indi') : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            arslanogluGroupFooter(),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 2. VELİ TAKİP PANELİ
// ===========================================================================
class VeliPaneli extends StatefulWidget {
  const VeliPaneli({super.key});

  @override
  State<VeliPaneli> createState() => _VeliPaneliState();
}

class _VeliPaneliState extends State<VeliPaneli> {
  String? token;
  Ogrenci? veliOgrencisi;
  ServisHatti? ogrenciServisi;
  Map<String, String> servisDurumu = {};
  Map<String, dynamic>? duyuru;
  String aktifNobetciAd = 'Öğretmen';
  bool yukleniyor = false;
  Timer? otoYenileyici;

  final TextEditingController noController = TextEditingController();
  final TextEditingController telController = TextEditingController();

  @override
  void initState() {
    super.initState();
    kayitliVeliyiYukle();
    otoYenileyici = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && token != null && veliOgrencisi != null && !yukleniyor) {
        veriyiYenile(sessiz: true);
      }
    });
  }

  @override
  void dispose() {
    otoYenileyici?.cancel();
    noController.dispose();
    telController.dispose();
    super.dispose();
  }

  void veriyiUygula(Map<String, dynamic> veri) {
    final ogrList = ogrencileriCoz(veri['ogrenciler']);
    final srvList = servisleriCoz(veri['servisler'], ogrList);
    final rawSrvDurum = veri['servisDurumu'];
    final Map<String, String> yeniSrvDurum = {};
    if (rawSrvDurum is Map) {
      rawSrvDurum.forEach((k, v) {
        yeniSrvDurum[k.toString()] = (v ?? '').toString();
      });
    }
    final rawDuyuru = veri['duyuru'];
    setState(() {
      veliOgrencisi = ogrList.isNotEmpty ? ogrList.first : null;
      ogrenciServisi = srvList.isNotEmpty ? srvList.first : null;
      servisDurumu = yeniSrvDurum;
      duyuru = rawDuyuru is Map ? Map<String, dynamic>.from(rawDuyuru) : null;
      aktifNobetciAd = aktifNobetciAdiniCoz(veri);
    });
  }

  Future<void> kayitliVeliyiYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitliNo = prefs.getString('balsuyu_veli_ogr_no');
    if (kayitliNo != null && mounted) noController.text = kayitliNo;
    final kayitliTok = prefs.getString('balsuyu_veli_token');
    if (kayitliTok == null || kayitliTok.isEmpty) return;

    if (mounted) setState(() => yukleniyor = true);
    final res = await apiGet({'islem': 'durum_getir', 'token': kayitliTok});
    if (!mounted) return;
    if (res['basarili'] == true) {
      token = kayitliTok;
      veriyiUygula(res);
    } else if (res['yetkisiz'] == true) {
      await prefs.remove('balsuyu_veli_token');
    }
    if (mounted) setState(() => yukleniyor = false);
  }

  Future<void> veriyiYenile({bool sessiz = false}) async {
    if (token == null) return;
    if (!sessiz && mounted) setState(() => yukleniyor = true);
    final res = await apiGet({'islem': 'durum_getir', 'token': token!});
    if (!mounted) return;
    if (res['basarili'] == true) {
      veriyiUygula(res);
    } else if (res['yetkisiz'] == true) {
      await veliCikisYap();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Oturum süresi doldu, lütfen tekrar giriş yapınız.'),
          ),
        );
      }
    } else if (!sessiz) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'Veriler yenilenemedi.').toString()),
        ),
      );
    }
    if (!sessiz && mounted) setState(() => yukleniyor = false);
  }

  Future<void> veliGirisYap() async {
    final girilenNo = noController.text.trim();
    final girilenTel = telController.text.trim();
    if (girilenNo.isEmpty || girilenTel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Okul numarası ve telefon boş bırakılamaz.'),
        ),
      );
      return;
    }

    setState(() => yukleniyor = true);
    final res = await apiPost({
      'islem': 'GIRIS_YAP',
      'rol': 'veli',
      'okulNo': girilenNo,
      'veliTel': girilenTel,
    });
    if (!mounted) return;
    setState(() => yukleniyor = false);

    if (res['basarili'] == true &&
        res['token'] != null &&
        res['veri'] is Map<String, dynamic>) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_veli_token', res['token'].toString());
      await prefs.setString('balsuyu_veli_ogr_no', girilenNo);
      token = res['token'].toString();
      telController.clear();
      veriyiUygula(res['veri'] as Map<String, dynamic>);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text((res['hata'] ?? 'Giriş başarısız.').toString()),
        ),
      );
    }
  }

  Future<void> veliCikisYap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('balsuyu_veli_token');
    if (!mounted) return;
    setState(() {
      token = null;
      veliOgrencisi = null;
      ogrenciServisi = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (veliOgrencisi == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  mebLogoRozeti(),
                  const SizedBox(height: 16),
                  const Text(
                    'BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Veli Bilgilendirme ve Canlı Takip Girişi',
                    style: TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.teal.withAlpha(77)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Öğrencinin Okul Numarası:',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: noController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Örn: 101',
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Kayıtlı Telefon Numaranız:',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: telController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Örn: 05551112233',
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 46),
                          ),
                          icon: yukleniyor
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.family_restroom),
                          label: Text(
                            yukleniyor
                                ? 'Kontrol Ediliyor...'
                                : 'Öğrencimi Görüntüle',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: yukleniyor ? null : veliGirisYap,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  arslanogluGroupFooter(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final soforAdi = ogrenciServisi?.soforAdi ?? 'Bilinmiyor';
    final soforTel = ogrenciServisi?.soforTel ?? '-';
    final adim = veliOgrencisi!.adim;
    final sonSaat = veliOgrencisi!.saat;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E26),
        foregroundColor: Colors.white,
        elevation: 3,
        title: Row(
          children: [
            mebLogoRozeti(),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BALSUYU MTAL — VELİ TAKİP',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  Text(
                    'Nöbetçi: $aktifNobetciAd',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.tealAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.refresh, color: Colors.tealAccent, size: 20),
            tooltip: 'Canlı Yenile',
            onPressed: yukleniyor ? null : () => veriyiYenile(),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
            tooltip: 'Çıkış Yap',
            onPressed: veliCikisYap,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              duyuruBandiWidget(duyuru),
              soforUyariBandiWidget(servisDurumu),
              if (veliOgrencisi!.izinli.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade900.withAlpha(180),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purpleAccent),
                  ),
                  child: Text(
                    '📋 İdare Bilgisi: Öğrenciniz bugün (${veliOgrencisi!.izinli == 'SABAH' ? 'Sabah' : (veliOgrencisi!.izinli == 'AKSAM' ? 'Akşam' : 'Tüm Gün')}) okul yönetimi tarafından İZİNLİ işaretlenmiştir.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.teal.withAlpha(77)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.teal.shade700,
                      child: const Icon(Icons.face_rounded,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            veliOgrencisi!.adSoyad,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'No: ${veliOgrencisi!.id} | Sınıf: ${veliOgrencisi!.sinif}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade400),
                          ),
                          Text(
                            'Bindiği Durak: ${veliOgrencisi!.koyDurak}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (sonSaat.isNotEmpty)
                            Text(
                              'Son Hareket Saati: $sonSaat',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.amberAccent,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _zamanCizelgesiSatiri(
                '1. Sabah Köyden Biniş',
                'Öğrenci köy durağından servise bindi.',
                adim >= 1,
                adim == 1 ? sonSaat : '',
              ),
              _zamanCizelgesiSatiri(
                '2. Sabah Okula Varış',
                'Öğrenci okula ulaştı, derste.',
                adim >= 2,
                adim == 2 ? sonSaat : '',
              ),
              _zamanCizelgesiSatiri(
                '3. Akşam Okuldan Çıkış',
                'Öğrenci okul çıkışı servise bindi, köye geliyor.',
                adim >= 3,
                adim == 3 ? sonSaat : '',
              ),
              _zamanCizelgesiSatiri(
                '4. Akşam Köye Varış',
                'Öğrenci köy durağında indi, eve ulaştı.',
                adim >= 4,
                adim == 4 ? sonSaat : '',
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Plaka: ${veliOgrencisi!.plaka} | Şoför: $soforAdi',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Şoför Tel: $soforTel',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                      icon: const Icon(Icons.phone, size: 14),
                      label: const Text(
                        'Şoförü Ara',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => telefonlaAra(context, soforTel),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              arslanogluGroupFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zamanCizelgesiSatiri(
    String baslik,
    String aciklama,
    bool tamamlandi,
    String saatEtiket,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tamamlandi
            ? Colors.teal.shade900.withAlpha(80)
            : const Color(0xFF1E293B).withAlpha(130),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: tamamlandi ? Colors.tealAccent.withAlpha(130) : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            tamamlandi
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: tamamlandi ? Colors.tealAccent : Colors.grey.shade600,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  baslik,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: tamamlandi ? Colors.white : Colors.grey,
                  ),
                ),
                Text(
                  aciklama,
                  style: TextStyle(
                    fontSize: 10,
                    color: tamamlandi ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (saatEtiket.isNotEmpty)
            Text(
              saatEtiket,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.tealAccent,
              ),
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 3. ŞOFÖR PANELİ
// ===========================================================================
class SoforPaneli extends StatefulWidget {
  const SoforPaneli({super.key});

  @override
  State<SoforPaneli> createState() => _SoforPaneliState();
}

class _SoforPaneliState extends State<SoforPaneli> {
  String? token;
  ServisHatti? soforServisi;
  Map<String, String> servisDurumu = {};
  Map<String, dynamic>? duyuru;
  bool yukleniyor = false;
  Timer? otoYenileyici;

  final TextEditingController telController = TextEditingController();

  @override
  void initState() {
    super.initState();
    kayitliSoforuYukle();
    otoYenileyici = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && token != null && soforServisi != null && !yukleniyor) {
        veriyiYenile(sessiz: true);
      }
    });
  }

  @override
  void dispose() {
    otoYenileyici?.cancel();
    telController.dispose();
    super.dispose();
  }

  void veriyiUygula(Map<String, dynamic> veri) {
    final ogrList = ogrencileriCoz(veri['ogrenciler']);
    final srvList = servisleriCoz(veri['servisler'], ogrList);
    final rawSrvDurum = veri['servisDurumu'];
    final Map<String, String> yeniSrvDurum = {};
    if (rawSrvDurum is Map) {
      rawSrvDurum.forEach((k, v) {
        yeniSrvDurum[k.toString()] = (v ?? '').toString();
      });
    }
    final rawDuyuru = veri['duyuru'];
    setState(() {
      soforServisi = srvList.isNotEmpty ? srvList.first : null;
      servisDurumu = yeniSrvDurum;
      duyuru = rawDuyuru is Map ? Map<String, dynamic>.from(rawDuyuru) : null;
    });
  }

  Future<void> _soforDurumGonder(String durumTuru, String mesaj) async {
    if (token == null || soforServisi == null) return;
    final res = await apiPost({
      'token': token,
      'islem': 'SOFOR_DURUM_BILDIR',
      'durumTuru': durumTuru,
      'mesaj': mesaj,
      'plaka': soforServisi!.plaka,
      'koy': soforServisi!.guzergah,
      'adSoyad': 'Şoför: ${soforServisi!.soforAdi}',
      'yontem': 'Şoför Bildirimi',
      'ogretmen': soforServisi!.soforAdi,
    });
    if (!mounted) return;
    if (res['basarili'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              durumTuru == 'ARIZA' ? Colors.red.shade900 : Colors.teal.shade800,
          content: Text(
            durumTuru == 'NORMAL'
                ? '✅ Normal sefere dönüldüğü bildirildi.'
                : '✅ Bildiriminiz idareye, öğretmenlere ve velilere iletildi!',
          ),
        ),
      );
      veriyiYenile(sessiz: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'Bildirim gönderilemedi.').toString()),
        ),
      );
    }
  }

  void soforDurumPenceresiAc() {
    final notController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.amberAccent,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ GECİKME / ARIZA BİLDİRİMİ',
              style: TextStyle(
                color: Colors.amberAccent,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bildiriminiz anında okul müdürüne, nöbetçi öğretmene ve velilere görünür.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'İsteğe bağlı kısa açıklama (örn: 15 dk gecikme)...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
              ),
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: const Text(
                'Trafik / Yol Nedeniyle Gecikme (10-15 dk)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              onPressed: () {
                final not = notController.text.trim();
                Navigator.pop(ctx);
                _soforDurumGonder(
                  'GECIKME',
                  not.isNotEmpty ? not : 'Trafik / yol nedeniyle 10-15 dk gecikme',
                );
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
              ),
              icon: const Icon(Icons.build_circle_rounded, size: 18),
              label: const Text(
                'Araç Arızası Bildir (İdareye Acil E-Posta)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              onPressed: () {
                final not = notController.text.trim();
                Navigator.pop(ctx);
                _soforDurumGonder(
                  'ARIZA',
                  not.isNotEmpty ? not : 'Araç arızası oluştu, yedek araç/destek gerekebilir',
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.greenAccent,
                side: const BorderSide(color: Colors.greenAccent),
                minimumSize: const Size(double.infinity, 40),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text(
                'Sorun Giderildi — Normal Sefere Dönüldü',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _soforDurumGonder('NORMAL', 'Normal seferde');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> kayitliSoforuYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitliTok = prefs.getString('balsuyu_sofor_token');
    if (kayitliTok == null || kayitliTok.isEmpty) return;

    if (mounted) setState(() => yukleniyor = true);
    final res = await apiGet({'islem': 'durum_getir', 'token': kayitliTok});
    if (!mounted) return;
    if (res['basarili'] == true) {
      token = kayitliTok;
      veriyiUygula(res);
    } else if (res['yetkisiz'] == true) {
      await prefs.remove('balsuyu_sofor_token');
    }
    if (mounted) setState(() => yukleniyor = false);
  }

  Future<void> veriyiYenile({bool sessiz = false}) async {
    if (token == null) return;
    if (!sessiz && mounted) setState(() => yukleniyor = true);
    final res = await apiGet({'islem': 'durum_getir', 'token': token!});
    if (!mounted) return;
    if (res['basarili'] == true) {
      veriyiUygula(res);
    } else if (res['yetkisiz'] == true) {
      await soforCikisYap();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Oturum süresi doldu, lütfen tekrar giriş yapınız.'),
          ),
        );
      }
    } else if (!sessiz) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'Veriler yenilenemedi.').toString()),
        ),
      );
    }
    if (!sessiz && mounted) setState(() => yukleniyor = false);
  }

  Future<void> soforGirisYap() async {
    final girilenTel = telController.text.trim();
    if (girilenTel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Lütfen telefon numaranızı giriniz.'),
        ),
      );
      return;
    }

    setState(() => yukleniyor = true);
    final res = await apiPost({
      'islem': 'GIRIS_YAP',
      'rol': 'sofor',
      'soforTel': girilenTel,
    });
    if (!mounted) return;
    setState(() => yukleniyor = false);

    if (res['basarili'] == true &&
        res['token'] != null &&
        res['veri'] is Map<String, dynamic>) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_sofor_token', res['token'].toString());
      token = res['token'].toString();
      telController.clear();
      veriyiUygula(res['veri'] as Map<String, dynamic>);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text((res['hata'] ?? 'Giriş başarısız.').toString()),
        ),
      );
    }
  }

  Future<void> soforCikisYap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('balsuyu_sofor_token');
    if (!mounted) return;
    setState(() {
      token = null;
      soforServisi = null;
    });
  }

  void yedekQrPenceresiAc() {
    if (soforServisi == null) return;
    final plaka = soforServisi!.plaka;
    final normPlaka = normalizePlaka(plaka);
    final qrKodVerisi = 'BALSUYU_SERVIS_$normPlaka';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'YEDEK SERVİS QR KODU',
              style: TextStyle(
                color: Colors.amberAccent,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$plaka — Camdaki kod okunamıyorsa öğretmene bu ekranı tutunuz.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: qrKodVerisi,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              qrKodVerisi,
              style: const TextStyle(
                color: Colors.tealAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (soforServisi == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  mebLogoRozeti(),
                  const SizedBox(height: 16),
                  const Text(
                    'BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Servis Kaptanı / Şoför Girişi',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.withAlpha(77)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sistemde Kayıtlı Telefon Numaranız:',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: telController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Örn: 05551234567',
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.black87,
                            minimumSize: const Size(double.infinity, 46),
                          ),
                          icon: yukleniyor
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black87,
                                  ),
                                )
                              : const Icon(Icons.directions_bus_rounded),
                          label: Text(
                            yukleniyor
                                ? 'Kontrol Ediliyor...'
                                : 'Servisimi Aç ve Başla',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: yukleniyor ? null : soforGirisYap,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  arslanogluGroupFooter(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final ogrenciler = soforServisi!.ogrenciler;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 3,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${soforServisi!.plaka} — Kaptan Paneli',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.amberAccent,
              ),
            ),
            Text(
              'Şoför: ${soforServisi!.soforAdi}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded,
                color: Colors.orangeAccent, size: 24),
            tooltip: 'Gecikme / Arıza Bildir',
            onPressed: soforDurumPenceresiAc,
          ),
          IconButton(
            icon:
                const Icon(Icons.refresh, color: Colors.tealAccent, size: 22),
            tooltip: 'Yenile',
            onPressed: yukleniyor ? null : () => veriyiYenile(),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_2_rounded,
                color: Colors.amberAccent, size: 26),
            tooltip: 'Yedek QR Kodumu Göster',
            onPressed: yedekQrPenceresiAc,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış',
            onPressed: soforCikisYap,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                children: [
                  duyuruBandiWidget(duyuru),
                  soforUyariBandiWidget(servisDurumu),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: ogrenciler.length,
                itemBuilder: (context, index) {
                  final ogr = ogrenciler[index];
                  final bool izinliMi = ogr.izinli.isNotEmpty;
                  final Color noktaRenk = izinliMi
                      ? Colors.purpleAccent
                      : (ogr.durum == 'serviste'
                          ? Colors.greenAccent
                          : (ogr.durum == 'indi'
                              ? Colors.lightBlueAccent
                              : Colors.grey));
                  return Card(
                    color: izinliMi
                        ? const Color(0xFF2E1065)
                        : const Color(0xFF1E293B),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        izinliMi ? Icons.event_busy_rounded : Icons.circle,
                        color: noktaRenk,
                        size: izinliMi ? 18 : 14,
                      ),
                      title: Text(
                        maskeleSoyad(ogr.adSoyad),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Durak: ${ogr.koyDurak} • ${adimKisaEtiket(ogr)}',
                        style: TextStyle(
                          color: izinliMi ? Colors.purple.shade200 : Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                      trailing: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade800,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.phone, size: 14),
                        label: const Text('Ara'),
                        onPressed: () => akilliAramaPenceresi(
                          context,
                          maskeleSoyad(ogr.adSoyad),
                          ogr.veliTel,
                          ogr.ogrenciTel,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 4. ÖĞRETMEN (NÖBETÇİ) PANELİ
// ===========================================================================
class OgretmenPaneli extends StatefulWidget {
  const OgretmenPaneli({super.key});

  @override
  State<OgretmenPaneli> createState() => _OgretmenPaneliState();
}

class _OgretmenPaneliState extends State<OgretmenPaneli> {
  String? token;
  bool girisYapildi = false;
  bool yukleniyor = false;
  bool islemYapiliyor = false;
  String bugunGun = getBugununGunu();
  List<NobetciOgretmen> nobetciler = [];
  NobetciOgretmen? seciliOgretmen;
  List<ServisHatti> servisler = [];
  List<Ogrenci> tumOgrenciler = [];
  int seciliServisIndex = 0;
  Timer? otoYenileyici;

  final TextEditingController pinController = TextEditingController();
  final TextEditingController genelAramaController = TextEditingController();
  String aramaKelimesi = '';

  bool gorevBasladi = false;
  String gorevSaati = '';
  Map<String, Map<String, String>> servisDurumlari = {};
  Map<String, dynamic>? duyuru;
  List<Map<String, dynamic>> guvenlikUyarilari = [];
  int kuyrukSayisi = 0;

  @override
  void initState() {
    super.initState();
    baslat();
    _kuyruguKontrolEt(sessiz: true);
    otoYenileyici = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          girisYapildi &&
          token != null &&
          !yukleniyor &&
          !islemYapiliyor) {
        _kuyruguKontrolEt(sessiz: true);
        verileriYenile(sessiz: true);
      }
    });
  }

  Future<void> _kuyruguKontrolEt({bool sessiz = false}) async {
    final s = await OfflineKuyruk.sayi();
    if (mounted && s != kuyrukSayisi) setState(() => kuyrukSayisi = s);
    if (s <= 0) return;
    final sonuc = await OfflineKuyruk.gonder();
    if (!mounted) return;
    setState(() => kuyrukSayisi = sonuc['kalan'] ?? 0);
    if ((sonuc['gonderilen'] ?? 0) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal.shade800,
          content: Text(
            '✅ Bekleyen ${sonuc['gonderilen']} çevrimdışı kayıt buluta aktarıldı!',
          ),
        ),
      );
      verileriYenile(sessiz: true);
    } else if (!sessiz && (sonuc['kalan'] ?? 0) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('İnternet henüz yok, kayıtlar cihazda güvende bekliyor.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    otoYenileyici?.cancel();
    pinController.dispose();
    genelAramaController.dispose();
    super.dispose();
  }

  Future<void> baslat() async {
    setState(() => yukleniyor = true);
    final listeRes = await apiGet({'islem': 'nobetci_listesi'});
    if (mounted && listeRes['basarili'] == true) {
      final yuklenen = nobetcileriCoz(listeRes['nobetciler']);
      final gunStr = (listeRes['bugunGun'] ?? getBugununGunu()).toString();
      NobetciOgretmen? varsayilan;
      for (final n in yuklenen) {
        if (n.gun.toLowerCase() == gunStr.toLowerCase()) {
          varsayilan = n;
          break;
        }
      }
      varsayilan ??= yuklenen.isNotEmpty ? yuklenen.first : null;
      setState(() {
        nobetciler = yuklenen;
        bugunGun = gunStr;
        seciliOgretmen = varsayilan;
      });
    }

    final prefs = await SharedPreferences.getInstance();
    final kayitliTok = prefs.getString('balsuyu_ogretmen_token');
    final kayitliAd = prefs.getString('balsuyu_ogretmen_ad');
    if (kayitliTok != null && kayitliTok.isNotEmpty) {
      final res = await apiGet({'islem': 'durum_getir', 'token': kayitliTok});
      if (mounted) {
        if (res['basarili'] == true) {
          token = kayitliTok;
          if (kayitliAd != null) {
            for (final n in nobetciler) {
              if (n.adSoyad == kayitliAd) {
                seciliOgretmen = n;
                break;
              }
            }
          }
          veriyiUygula(res);
          setState(() => girisYapildi = true);
        } else if (res['yetkisiz'] == true) {
          await prefs.remove('balsuyu_ogretmen_token');
        }
      }
    }
    if (mounted) setState(() => yukleniyor = false);
  }

  void veriyiUygula(Map<String, dynamic> veri) {
    final oncekiPlaka =
        (servisler.isNotEmpty && seciliServisIndex < servisler.length)
            ? normalizePlaka(servisler[seciliServisIndex].plaka)
            : '';

    final ogrList = ogrencileriCoz(veri['ogrenciler']);
    final srvList = servisleriCoz(veri['servisler'], ogrList);
    final nbList = nobetcileriCoz(veri['nobetciler']);
    final gd = veri['gunlukDurum'];

    bool gBasladi = false;
    String gSaati = '';
    final Map<String, Map<String, String>> yeniDurumlar = {};

    if (gd is Map) {
      gBasladi = gd['ogretmenGorevde'] == true;
      gSaati = (gd['ogretmenGorevSaati'] ?? '').toString();
      final rawSd = gd['servisDurumlari'];
      if (rawSd is Map) {
        rawSd.forEach((k, v) {
          if (v is Map) {
            yeniDurumlar[normalizePlaka(k.toString())] = {
              'sabahGeldi': (v['sabahGeldi'] ?? '').toString(),
              'sabahTamam': (v['sabahTamam'] ?? '').toString(),
              'aksamHareket': (v['aksamHareket'] ?? '').toString(),
              'soforUyarisi': (v['soforUyarisi'] ?? '').toString(),
              'soforUyariTuru': (v['soforUyariTuru'] ?? '').toString(),
              'soforUyariSaati': (v['soforUyariSaati'] ?? '').toString(),
            };
          }
        });
      }
    }

    int yeniIndex = 0;
    if (oncekiPlaka.isNotEmpty) {
      final bulunan =
          srvList.indexWhere((s) => normalizePlaka(s.plaka) == oncekiPlaka);
      if (bulunan != -1) yeniIndex = bulunan;
    } else if (seciliServisIndex < srvList.length) {
      yeniIndex = seciliServisIndex;
    }

    final rawDuyuru = veri['duyuru'];
    final rawGuvenlik = veri['guvenlikUyarilari'];
    final List<Map<String, dynamic>> yeniGuvenlik = [];
    if (rawGuvenlik is List) {
      for (final g in rawGuvenlik) {
        if (g is Map) yeniGuvenlik.add(Map<String, dynamic>.from(g));
      }
    }

    setState(() {
      tumOgrenciler = ogrList;
      servisler = srvList;
      if (nbList.isNotEmpty) nobetciler = nbList;
      seciliServisIndex = yeniIndex;
      gorevBasladi = gBasladi;
      gorevSaati = gSaati;
      servisDurumlari = yeniDurumlar;
      duyuru = rawDuyuru is Map ? Map<String, dynamic>.from(rawDuyuru) : null;
      guvenlikUyarilari = yeniGuvenlik;
    });
  }

  Future<void> _yetkisizKontrol(Map<String, dynamic> res) async {
    if (res['yetkisiz'] == true) {
      await ogretmenCikisYap();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Oturum süresi doldu, lütfen tekrar giriş yapınız.'),
          ),
        );
      }
    }
  }

  Future<void> verileriYenile({bool sessiz = false}) async {
    if (token == null) return;
    if (!sessiz && mounted) setState(() => yukleniyor = true);
    final res = await apiGet({'islem': 'durum_getir', 'token': token!});
    if (!mounted) return;
    if (res['basarili'] == true) {
      veriyiUygula(res);
    } else if (res['yetkisiz'] == true) {
      await _yetkisizKontrol(res);
    } else if (!sessiz) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'Veriler yenilenemedi.').toString()),
        ),
      );
    }
    if (!sessiz && mounted) setState(() => yukleniyor = false);
  }

  Future<void> pinKontrolEt() async {
    if (seciliOgretmen == null) return;
    final pin = pinController.text.trim();
    if (pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Lütfen PIN kodunu giriniz.'),
        ),
      );
      return;
    }

    setState(() => yukleniyor = true);
    final res = await apiPost({
      'islem': 'GIRIS_YAP',
      'rol': 'ogretmen',
      'ogretmenAdi': seciliOgretmen!.adSoyad,
      'pin': pin,
    });
    if (!mounted) return;
    setState(() => yukleniyor = false);

    if (res['basarili'] == true &&
        res['token'] != null &&
        res['veri'] is Map<String, dynamic>) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_ogretmen_token', res['token'].toString());
      await prefs.setString('balsuyu_ogretmen_ad', seciliOgretmen!.adSoyad);
      token = res['token'].toString();
      pinController.clear();
      veriyiUygula(res['veri'] as Map<String, dynamic>);
      setState(() => girisYapildi = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 4),
          content: Text((res['hata'] ?? 'Giriş başarısız.').toString()),
        ),
      );
    }
  }

  Future<void> ogretmenCikisYap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('balsuyu_ogretmen_token');
    if (!mounted) return;
    setState(() {
      token = null;
      girisYapildi = false;
      pinController.clear();
    });
  }

  Future<void> _qrKameraAc({
    required bool sabahMi,
    required ServisHatti aktifServis,
  }) async {
    final sonuc = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => ServisQrTarayiciEkrani(
          sabahMi: sabahMi,
          beklenenPlaka: aktifServis.plaka,
          tumServisler: servisler,
        ),
      ),
    );
    if (!mounted || sonuc == null || sonuc['onay'] != true) return;

    ServisHatti hedefServis = aktifServis;
    if (sonuc['servis'] is ServisHatti) {
      hedefServis = sonuc['servis'] as ServisHatti;
      final idx = servisler.indexWhere(
        (s) => normalizePlaka(s.plaka) == normalizePlaka(hedefServis.plaka),
      );
      if (idx != -1 && idx != seciliServisIndex) {
        setState(() => seciliServisIndex = idx);
      }
    }

    await _servisKaydet(
      sabahMi: sabahMi,
      aktifServis: hedefServis,
      qrIleMi: sonuc['qr'] == true,
    );
  }

  void servisQrPenceresiAc({
    required bool sabahMi,
    required ServisHatti aktifServis,
  }) {
    final plaka = aktifServis.plaka;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 14),
            const Icon(Icons.qr_code_scanner,
                color: Colors.tealAccent, size: 40),
            const SizedBox(height: 8),
            Text(
              sabahMi
                  ? 'Sabah Servis Girişi ($plaka)'
                  : 'Akşam Servis Çıkışı ($plaka)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Servis camındaki veya şoför ekranındaki QR kodu kamera ile okutunuz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
              ),
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text(
                '1. Kamera ile QR Kodu Okut',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _qrKameraAc(
                  sabahMi: sabahMi,
                  aktifServis: aktifServis,
                );
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amberAccent,
                side: const BorderSide(color: Colors.amberAccent),
                minimumSize: const Size(double.infinity, 44),
              ),
              icon: const Icon(Icons.touch_app_rounded, size: 18),
              label: const Text(
                '2. QR Okunmuyor (Manuel Onayla)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _servisKaydet(
                  sabahMi: sabahMi,
                  aktifServis: aktifServis,
                  qrIleMi: false,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _servisKaydet({
    required bool sabahMi,
    required ServisHatti aktifServis,
    required bool qrIleMi,
  }) async {
    if (token == null || islemYapiliyor) return;
    setState(() => islemYapiliyor = true);

    final plaka = aktifServis.plaka;
    final normP = normalizePlaka(plaka);
    final yontemStr = qrIleMi ? 'QR Okutuldu' : 'Manuel (Öğretmen)';

    final res = await apiPost({
      'token': token,
      'plaka': plaka,
      'koy': aktifServis.guzergah,
      'adSoyad': 'Şoför: ${aktifServis.soforAdi}',
      'sinif': '-',
      'islem': sabahMi ? 'SERVIS_SABAH_GELDI' : 'SERVIS_AKSAM_HAREKET',
      'yontem': yontemStr,
      'ogretmen': seciliOgretmen?.adSoyad ?? 'Nöbetçi',
    });
    if (!mounted) return;
    setState(() => islemYapiliyor = false);

    if (res['basarili'] == true) {
      final now = DateTime.now();
      final saat = (res['saat'] != null && res['saat'].toString().isNotEmpty)
          ? res['saat'].toString()
          : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      setState(() {
        servisDurumlari.putIfAbsent(
          normP,
          () => {'sabahGeldi': '', 'sabahTamam': '', 'aksamHareket': ''},
        );
        if (sabahMi) {
          servisDurumlari[normP]!['sabahGeldi'] =
              '$saat (${qrIleMi ? 'QR' : 'MANUEL'})';
        } else {
          servisDurumlari[normP]!['aksamHareket'] =
              '$saat (${qrIleMi ? 'QR' : 'MANUEL'})';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              qrIleMi ? Colors.teal.shade900 : Colors.amber.shade900,
          content: Text(
            qrIleMi
                ? '$plaka QR ile Doğrulandı! ($saat)'
                : '$plaka MANUEL ONAYLANDI! ($saat)',
          ),
        ),
      );
    } else if (res['yetkisiz'] == true) {
      await _yetkisizKontrol(res);
    } else {
      if (res['yenile'] == true) {
        verileriYenile(sessiz: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'Kayıt gönderilemedi.').toString()),
        ),
      );
    }
  }

  void aksamCikisKontrolEt(ServisHatti aktifServis) {
    final sabahGelenler = aktifServis.ogrenciler
        .where((o) => o.adim >= 2 && o.izinli != 'TUM_GUN' && o.izinli != 'AKSAM')
        .toList();
    final aksamBinmeyenler = sabahGelenler.where((o) => o.adim < 3).toList();
    if (aksamBinmeyenler.isNotEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'EKSİK ÖĞRENCİ UYARISI!',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sabah ${aktifServis.plaka} servisiyle okula gelen ancak şu an serviste olmayan öğrenciler var:',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 10),
                ...aksamBinmeyenler.map(
                  (ogr) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withAlpha(80),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${ogr.adSoyad} (${ogr.sinif})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.phone,
                              color: Colors.greenAccent, size: 18),
                          tooltip: 'Ara',
                          onPressed: () => akilliAramaPenceresi(
                            context,
                            ogr.adSoyad,
                            ogr.veliTel,
                            ogr.ogrenciTel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Öğrenci izinli mi veya velisiyle mi ayrıldı?',
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('İptal', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(c);
                servisQrPenceresiAc(sabahMi: false, aktifServis: aktifServis);
              },
              child: const Text('Bilgimiz Var (İzinli) - Onayla'),
            ),
          ],
        ),
      );
    } else {
      servisQrPenceresiAc(sabahMi: false, aktifServis: aktifServis);
    }
  }

  Future<void> adimiIlerlet(Ogrenci ogr, String plaka) async {
    if (token == null || ogr.adim >= 4 || islemYapiliyor) return;
    String islemMetni = '';
    String yeniDurum = '';
    final int yeniAdim = ogr.adim + 1;
    if (ogr.adim == 0) {
      islemMetni = 'SABAH BİNDİ';
      yeniDurum = 'serviste';
    } else if (ogr.adim == 1) {
      islemMetni = 'SABAH İNDİ';
      yeniDurum = 'indi';
    } else if (ogr.adim == 2) {
      islemMetni = 'AKŞAM BİNDİ';
      yeniDurum = 'serviste';
    } else if (ogr.adim == 3) {
      islemMetni = 'AKŞAM İNDİ';
      yeniDurum = 'indi';
    } else {
      return;
    }

    final paket = {
      'token': token,
      'okulNo': ogr.id,
      'plaka': plaka,
      'koy': ogr.koyDurak,
      'adSoyad': ogr.adSoyad,
      'sinif': ogr.sinif,
      'islem': islemMetni,
      'yontem': 'Manuel (Öğretmen)',
      'ogretmen': seciliOgretmen?.adSoyad ?? 'Nöbetçi',
    };

    setState(() => islemYapiliyor = true);
    final res = await apiPost(paket);
    if (!mounted) return;
    setState(() => islemYapiliyor = false);

    if (res['basarili'] == true) {
      final now = DateTime.now().toUtc().add(const Duration(hours: 3));
      final saatStr = (res['saat'] != null && res['saat'].toString().isNotEmpty)
          ? res['saat'].toString()
          : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      setState(() {
        ogr.adim = yeniAdim;
        ogr.durum = yeniDurum;
        ogr.saat = saatStr;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal.shade800,
          content: Text('${ogr.adSoyad} ($islemMetni) kaydedildi!'),
        ),
      );
    } else if (res['agHatasi'] == true) {
      final yeniSayi =
          await OfflineKuyruk.ekle(paket, '${ogr.adSoyad} ($islemMetni)');
      final trNow = DateTime.now().toUtc().add(const Duration(hours: 3));
      final saatStr =
          '${trNow.hour.toString().padLeft(2, '0')}:${trNow.minute.toString().padLeft(2, '0')}';
      if (!mounted) return;
      setState(() {
        kuyrukSayisi = yeniSayi;
        ogr.adim = yeniAdim;
        ogr.durum = yeniDurum;
        ogr.saat = saatStr;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade900,
          content: Text(
            '📡 İnternet yok! ${ogr.adSoyad} ($islemMetni) cihazda saklandı, bağlantı gelince gönderilecek.',
          ),
        ),
      );
    } else if (res['yetkisiz'] == true) {
      await _yetkisizKontrol(res);
    } else {
      if (res['yenile'] == true) {
        verileriYenile(sessiz: true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'Kayıt gönderilemedi.').toString()),
        ),
      );
    }
  }

  void izinliPenceresiAc(Ogrenci ogr, String plaka) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.purpleAccent,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '📋 ${ogr.adSoyad} — İzinli Durumu',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sadece okul idaresi ve nöbetçi öğretmen izinli işaretleyebilir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 42),
              ),
              icon: const Icon(Icons.event_busy_rounded, size: 18),
              label: const Text('Tüm Gün İzinli (Binmeyecek)'),
              onPressed: () {
                Navigator.pop(ctx);
                _izinKaydet(ogr, plaka, 'OGRENCI_IZINLI', izinTuru: 'TUM_GUN');
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 42),
              ),
              icon: const Icon(Icons.wb_sunny_outlined, size: 18),
              label: const Text('Sadece Sabah İzinli'),
              onPressed: () {
                Navigator.pop(ctx);
                _izinKaydet(ogr, plaka, 'OGRENCI_IZINLI', izinTuru: 'SABAH');
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 42),
              ),
              icon: const Icon(Icons.nights_stay_outlined, size: 18),
              label: const Text('Sadece Akşam İzinli (Velisi Alacak)'),
              onPressed: () {
                Navigator.pop(ctx);
                _izinKaydet(ogr, plaka, 'OGRENCI_IZINLI', izinTuru: 'AKSAM');
              },
            ),
            if (ogr.izinli.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amberAccent,
                  side: const BorderSide(color: Colors.amberAccent),
                  minimumSize: const Size(double.infinity, 40),
                ),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('İzni Kaldır'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _izinKaydet(ogr, plaka, 'OGRENCI_IZIN_KALDIR');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _izinKaydet(
    Ogrenci ogr,
    String plaka,
    String islem, {
    String izinTuru = '',
  }) async {
    if (token == null || islemYapiliyor) return;
    setState(() => islemYapiliyor = true);
    final paket = <String, dynamic>{
      'token': token,
      'okulNo': ogr.id,
      'plaka': plaka,
      'koy': ogr.koyDurak,
      'adSoyad': ogr.adSoyad,
      'sinif': ogr.sinif,
      'islem': islem,
      'yontem': 'Öğretmen Onayı',
      'ogretmen': seciliOgretmen?.adSoyad ?? 'Nöbetçi',
    };
    if (izinTuru.isNotEmpty) paket['izinTuru'] = izinTuru;

    final res = await apiPost(paket);
    if (!mounted) return;
    setState(() => islemYapiliyor = false);

    if (res['basarili'] == true) {
      setState(() {
        ogr.izinli = islem == 'OGRENCI_IZIN_KALDIR' ? '' : izinTuru;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepPurple.shade700,
          content: Text(
            islem == 'OGRENCI_IZIN_KALDIR'
                ? '${ogr.adSoyad} izni kaldırıldı.'
                : '${ogr.adSoyad} izinli olarak kaydedildi.',
          ),
        ),
      );
    } else if (res['yetkisiz'] == true) {
      await _yetkisizKontrol(res);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'İzin kaydedilemedi.').toString()),
        ),
      );
    }
  }

  Future<void> adimiSifirla(Ogrenci ogr, String plaka) async {
    if (token == null || islemYapiliyor) return;
    setState(() => islemYapiliyor = true);

    final res = await apiPost({
      'token': token,
      'okulNo': ogr.id,
      'plaka': plaka,
      'koy': ogr.koyDurak,
      'adSoyad': ogr.adSoyad,
      'sinif': ogr.sinif,
      'islem': 'ADIM_SIFIRLA',
      'yontem': 'Manuel (Öğretmen)',
      'ogretmen': seciliOgretmen?.adSoyad ?? 'Nöbetçi',
    });
    if (!mounted) return;
    setState(() => islemYapiliyor = false);

    if (res['basarili'] == true) {
      setState(() {
        ogr.adim = 0;
        ogr.durum = 'binmedi';
        ogr.saat = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.blueGrey,
          content: Text('${ogr.adSoyad} adımı sıfırlandı.'),
        ),
      );
    } else if (res['yetkisiz'] == true) {
      await _yetkisizKontrol(res);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text((res['hata'] ?? 'Sıfırlanamadı.').toString()),
        ),
      );
    }
  }

  Color _kartRengi(int adim) {
    if (adim == 1) return const Color(0xFFE0F2FE);
    if (adim == 2) return const Color(0xFFFFEDD5);
    if (adim == 3) return const Color(0xFFDCFCE7);
    if (adim >= 4) return const Color(0xFFCCFBF1);
    return Colors.white;
  }

  Color _kartKenarlikRengi(int adim) {
    if (adim == 1) return Colors.lightBlueAccent;
    if (adim == 2) return Colors.orangeAccent;
    if (adim == 3) return Colors.greenAccent;
    if (adim >= 4) return Colors.teal;
    return Colors.grey.shade300;
  }

  Widget _ogretmenDurumRozeti(Ogrenci ogr) {
    if (ogr.adim == 1) {
      return Text(
        '1. Sabah Bindi: ${ogr.saat}',
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
      );
    }
    if (ogr.adim == 2) {
      return Text(
        '2. Okulda İndi: ${ogr.saat}',
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.deepOrange),
      );
    }
    if (ogr.adim == 3) {
      return Text(
        '3. Akşam Bindi: ${ogr.saat}',
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
      );
    }
    if (ogr.adim >= 4) {
      return Text(
        '4. Köyde İndi (Bitti): ${ogr.saat}',
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal),
      );
    }
    return const Text(
      'Henüz Binmedi',
      style: TextStyle(fontSize: 10, color: Colors.grey),
    );
  }

  String _siradakiButonMetni(int adim) {
    if (adim == 0) return '1. Sabah Bindi';
    if (adim == 1) return '2. Okula İndi';
    if (adim == 2) return '3. Akşam Bindi';
    if (adim == 3) return '4. Köyde İndi';
    return 'TAMAM';
  }

  @override
  Widget build(BuildContext context) {
    if (!girisYapildi) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  mebLogoRozeti(),
                  const SizedBox(height: 16),
                  const Text(
                    'BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade900,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Bugün: $bugunGun Nöbeti',
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.teal.withAlpha(77)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Nöbetçi Öğretmen / İdareci Seçimi:',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh,
                                  color: Colors.tealAccent, size: 18),
                              onPressed: yukleniyor ? null : baslat,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<NobetciOgretmen>(
                          value: nobetciler.contains(seciliOgretmen)
                              ? seciliOgretmen
                              : null,
                          dropdownColor: const Color(0xFF1E293B),
                          isExpanded: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: nobetciler
                              .map(
                                (n) => DropdownMenuItem(
                                  value: n,
                                  child: Text(
                                    '${n.adSoyad} (${n.gun})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => seciliOgretmen = val),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Giriş PIN Kodu:',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: pinController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          maxLength: 4,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            letterSpacing: 6,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            hintText: '••••',
                            hintStyle: const TextStyle(
                              color: Colors.white24,
                              letterSpacing: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 46),
                          ),
                          icon: yukleniyor
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.lock_open_rounded),
                          label: Text(
                            yukleniyor ? 'Doğrulanıyor...' : 'Paneli Aç',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: yukleniyor ? null : pinKontrolEt,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  arslanogluGroupFooter(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final aktifServis =
        (servisler.isNotEmpty && seciliServisIndex < servisler.length)
            ? servisler[seciliServisIndex]
            : null;
    final binenSayisi =
        aktifServis?.ogrenciler.where((o) => o.durum == 'serviste').length ?? 0;
    final inenSayisi =
        aktifServis?.ogrenciler.where((o) => o.adim == 2).length ?? 0;
    final eveUlasanSayisi =
        aktifServis?.ogrenciler.where((o) => o.adim >= 4).length ?? 0;
    final beklenenSayisi =
        aktifServis?.ogrenciler.where((o) => o.adim == 0).length ?? 0;

    final plaka = aktifServis?.plaka ?? '';
    final normPlaka = normalizePlaka(plaka);
    final durumMap = servisDurumlari[normPlaka] ?? {};
    final String sabahGeldiSaat = durumMap['sabahGeldi'] ?? '';
    final bool sabahGeldi = sabahGeldiSaat.isNotEmpty;
    final String sabahTamamSaat = durumMap['sabahTamam'] ?? '';
    final bool sabahTamam = sabahTamamSaat.isNotEmpty;
    final String aksamHareketSaat = durumMap['aksamHareket'] ?? '';
    final bool aksamHareket = aksamHareketSaat.isNotEmpty;

    final arananOgrenciler = aramaKelimesi.isEmpty
        ? (aktifServis?.ogrenciler ?? [])
        : tumOgrenciler.where((o) {
            final kelime = aramaKelimesi.toLowerCase();
            return o.id.contains(kelime) ||
                o.adSoyad.toLowerCase().contains(kelime);
          }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E26),
        foregroundColor: Colors.white,
        elevation: 3,
        title: Row(
          children: [
            mebLogoRozeti(),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BALSUYU MTAL — NÖBETÇİ PANELİ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    'Nöbetçi: ${seciliOgretmen?.adSoyad ?? 'Öğretmen'}',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.refresh, color: Colors.tealAccent, size: 20),
            tooltip: 'Canlı Yenile',
            onPressed: yukleniyor ? null : () => verileriYenile(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.picture_as_pdf_rounded,
                color: Colors.amberAccent, size: 22),
            tooltip: 'Resmi MEB PDF Raporları',
            onSelected: (secim) {
              if (token == null) return;
              if (secim == 'gunluk') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Resmi MEB İmzalı Günlük PDF Hazırlanıyor...'),
                  ),
                );
                linkAc(
                  context,
                  '$googleTabloWebhookUrl?islem=pdf_indir&token=$token',
                );
              } else if (secim == 'puantaj') {
                final tr = DateTime.now().toUtc().add(const Duration(hours: 3));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('MEB Aylık Servis Puantaj PDF Hazırlanıyor...'),
                  ),
                );
                linkAc(
                  context,
                  '$googleTabloWebhookUrl?islem=aylik_puantaj_pdf&yil=${tr.year}&ay=${tr.month}&token=$token',
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'gunluk',
                child: Text('📄 Günlük Resmi Yoklama PDF'),
              ),
              PopupMenuItem(
                value: 'puantaj',
                child: Text('🏛️ MEB Aylık Servis Puantaj PDF'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            tooltip: 'Çıkış',
            onPressed: ogretmenCikisYap,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: aktifServis == null
          ? const Center(child: Text('Kayıtlı servis bulunamadı.'))
          : Column(
              children: [
                if (duyuru != null ||
                    (durumMap['soforUyarisi'] ?? '').isNotEmpty ||
                    kuyrukSayisi > 0 ||
                    guvenlikUyarilari.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                    child: Column(
                      children: [
                        duyuruBandiWidget(duyuru),
                        soforUyariBandiWidget(durumMap),
                        kuyrukBandiWidget(
                            kuyrukSayisi, () => _kuyruguKontrolEt()),
                        if (guvenlikUyarilari.isNotEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade900,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '⚠️ SERVİSTEN İNMEYEN ÖĞRENCİ (${guvenlikUyarilari.length}): ${guvenlikUyarilari.map((u) => '${u['adSoyad']} (${u['plaka']})').take(3).join(', ')}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: gorevBasladi
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: gorevBasladi ? Colors.green : Colors.orange,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        gorevBasladi
                            ? Icons.verified
                            : Icons.access_time_filled,
                        color: gorevBasladi
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          gorevBasladi
                              ? 'Görev Başındasınız (Saat: $gorevSaati)'
                              : 'Henüz göreve başlama bildirimi yapmadınız!',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: gorevBasladi
                                ? Colors.green.shade900
                                : Colors.orange.shade900,
                          ),
                        ),
                      ),
                      if (!gorevBasladi)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: const Size(60, 28),
                          ),
                          onPressed: islemYapiliyor
                              ? null
                              : () async {
                                  if (token == null) return;
                                  setState(() => islemYapiliyor = true);
                                  final res = await apiPost({
                                    'token': token,
                                    'plaka': '-',
                                    'koy': 'Okul Girişi',
                                    'adSoyad':
                                        seciliOgretmen?.adSoyad ?? 'Nöbetçi',
                                    'sinif': '-',
                                    'islem': 'OGRETMEN_GOREVE_BASLADI',
                                    'yontem': 'Öğretmen Butonu',
                                    'ogretmen':
                                        seciliOgretmen?.adSoyad ?? 'Nöbetçi',
                                  });
                                  if (!mounted) return;
                                  setState(() => islemYapiliyor = false);
                                  if (res['basarili'] == true) {
                                    final now = DateTime.now();
                                    final s = (res['saat'] != null &&
                                            res['saat'].toString().isNotEmpty)
                                        ? res['saat'].toString()
                                        : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                                    setState(() {
                                      gorevBasladi = true;
                                      gorevSaati = s;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: Colors.green,
                                        content: Text(
                                          'Göreve başlama bildirimi müdüre iletildi!',
                                        ),
                                      ),
                                    );
                                  } else if (res['yetkisiz'] == true) {
                                    await _yetkisizKontrol(res);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: Colors.red.shade900,
                                        content: Text(
                                          (res['hata'] ??
                                                  'Bildirim gönderilemedi.')
                                              .toString(),
                                        ),
                                      ),
                                    );
                                  }
                                },
                          child: const Text(
                            'Göreve Başla',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  height: 40,
                  child: TextField(
                    controller: genelAramaController,
                    onChanged: (val) =>
                        setState(() => aramaKelimesi = val.trim()),
                    decoration: InputDecoration(
                      hintText: 'Öğrenci No veya İsimle Ara (Tüm Okul)...',
                      hintStyle:
                          const TextStyle(fontSize: 11, color: Colors.grey),
                      prefixIcon:
                          const Icon(Icons.search, size: 18, color: Colors.teal),
                      suffixIcon: aramaKelimesi.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                genelAramaController.clear();
                                setState(() => aramaKelimesi = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.teal.shade200),
                      ),
                    ),
                  ),
                ),
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: sabahGeldi
                                ? Colors.teal.shade900
                                : Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          icon: Icon(
                            sabahGeldi
                                ? Icons.check_circle
                                : Icons.qr_code_scanner,
                            size: 14,
                          ),
                          label: Text(
                            sabahGeldi
                                ? '1. Geldi ($sabahGeldiSaat)'
                                : '1. Servis Geldi',
                            style: const TextStyle(
                                fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                          onPressed: (sabahGeldi || islemYapiliyor)
                              ? null
                              : () => servisQrPenceresiAc(
                                    sabahMi: true,
                                    aktifServis: aktifServis,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: sabahTamam
                                ? Colors.blue.shade900
                                : (sabahGeldi
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade400),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          icon: Icon(
                            sabahTamam
                                ? Icons.verified
                                : Icons.check_circle_outline,
                            size: 14,
                          ),
                          label: Text(
                            sabahTamam
                                ? '2. Bitti ($sabahTamamSaat)'
                                : '2. Sabah Bitti',
                            style: const TextStyle(
                                fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                          onPressed: (!sabahGeldi ||
                                  sabahTamam ||
                                  islemYapiliyor)
                              ? null
                              : () async {
                                  if (token == null) return;
                                  setState(() => islemYapiliyor = true);
                                  final res = await apiPost({
                                    'token': token,
                                    'plaka': aktifServis.plaka,
                                    'koy': aktifServis.guzergah,
                                    'adSoyad': 'Şoför: ${aktifServis.soforAdi}',
                                    'sinif': '-',
                                    'islem': 'SERVIS_SABAH_TAMAM',
                                    'yontem': 'Öğretmen Onayı',
                                    'ogretmen':
                                        seciliOgretmen?.adSoyad ?? 'Nöbetçi',
                                  });
                                  if (!mounted) return;
                                  setState(() => islemYapiliyor = false);
                                  if (res['basarili'] == true) {
                                    final now = DateTime.now();
                                    final s = (res['saat'] != null &&
                                            res['saat'].toString().isNotEmpty)
                                        ? res['saat'].toString()
                                        : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                                    setState(() {
                                      servisDurumlari.putIfAbsent(
                                        normPlaka,
                                        () => {
                                          'sabahGeldi': '',
                                          'sabahTamam': '',
                                          'aksamHareket': '',
                                        },
                                      );
                                      servisDurumlari[normPlaka]!['sabahTamam'] =
                                          s;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: Colors.blue.shade900,
                                        content: Text(
                                          '${aktifServis.plaka} Sabah İndirme Bitti! ($s)',
                                        ),
                                      ),
                                    );
                                    verileriYenile(sessiz: true);
                                  } else if (res['yetkisiz'] == true) {
                                    await _yetkisizKontrol(res);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: Colors.red.shade900,
                                        content: Text(
                                          (res['hata'] ??
                                                  'Kayıt gönderilemedi.')
                                              .toString(),
                                        ),
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: aksamHareket
                                ? Colors.amber.shade900
                                : Colors.amber.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          icon: Icon(
                            aksamHareket
                                ? Icons.done_all
                                : Icons.directions_bus,
                            size: 14,
                          ),
                          label: Text(
                            aksamHareket
                                ? '3. Yolda ($aksamHareketSaat)'
                                : '3. Hareket (QR)',
                            style: const TextStyle(
                                fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                          onPressed: (aksamHareket || islemYapiliyor)
                              ? null
                              : () => aksamCikisKontrolEt(aktifServis),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: servisler.length,
                    itemBuilder: (context, index) {
                      final seciliMi = index == seciliServisIndex;
                      final s = servisler[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          selected: seciliMi,
                          label: Text(
                            s.plaka,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: seciliMi ? Colors.white : Colors.black87,
                            ),
                          ),
                          selectedColor: const Color(0xFF0A2E26),
                          backgroundColor: Colors.white,
                          onSelected: (val) => setState(() {
                            seciliServisIndex = index;
                            genelAramaController.clear();
                            aramaKelimesi = '';
                          }),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  child: Row(
                    children: [
                      _sayacKutusu(
                          'Serviste', binenSayisi, Colors.green.shade700),
                      const SizedBox(width: 5),
                      _sayacKutusu('Okulda', inenSayisi, Colors.blue.shade700),
                      const SizedBox(width: 5),
                      _sayacKutusu(
                          'Eve Ulaştı', eveUlasanSayisi, Colors.teal.shade700),
                      const SizedBox(width: 5),
                      _sayacKutusu(
                          'Beklenen', beklenenSayisi, Colors.orange.shade800),
                    ],
                  ),
                ),
                Expanded(
                  child: arananOgrenciler.isEmpty
                      ? const Center(
                          child: Text(
                            'Öğrenci bulunamadı.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 2),
                          itemCount: arananOgrenciler.length,
                          itemBuilder: (context, index) {
                            final ogr = arananOgrenciler[index];
                            final buOgrencininPlakasi = ogr.plaka;
                            final baskaServisteMi = aramaKelimesi.isNotEmpty &&
                                normalizePlaka(buOgrencininPlakasi) !=
                                    normPlaka;
                            final sinifKisa = ogr.sinif.isNotEmpty
                                ? ogr.sinif.split('/')[0]
                                : '-';

                            return Card(
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 6),
                              color: _kartRengi(ogr.adim),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: _kartKenarlikRengi(ogr.adim),
                                  width: 1.2,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.white,
                                      child: Text(
                                        sinifKisa,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ogr.adSoyad,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Color(0xFF1E293B),
                                            ),
                                          ),
                                          Text(
                                            'No: ${ogr.id} | Sınıf: ${ogr.sinif} | Durak: ${ogr.koyDurak}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          if (ogr.izinli.isNotEmpty)
                                            Text(
                                              '📋 İZİNLİ (${ogr.izinli == 'SABAH' ? 'Sabah' : (ogr.izinli == 'AKSAM' ? 'Akşam' : 'Tüm Gün')})',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.deepPurple,
                                              ),
                                            )
                                          else
                                            _ogretmenDurumRozeti(ogr),
                                          if (baskaServisteMi)
                                            Text(
                                              'SERVİSİ: $buOgrencininPlakasi',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.indigo,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        if (baskaServisteMi)
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.indigo,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 3),
                                              minimumSize: const Size(60, 26),
                                            ),
                                            onPressed: () {
                                              final oIndex =
                                                  servisler.indexWhere(
                                                (s) =>
                                                    normalizePlaka(s.plaka) ==
                                                    normalizePlaka(
                                                        buOgrencininPlakasi),
                                              );
                                              if (oIndex != -1) {
                                                setState(() {
                                                  seciliServisIndex = oIndex;
                                                  genelAramaController.clear();
                                                  aramaKelimesi = '';
                                                });
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '$buOgrencininPlakasi servisine yönlendirildiniz!',
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            child: const Text(
                                              'Servise Git',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          )
                                        else ...[
                                          if (ogr.adim < 4 &&
                                              ogr.izinli != 'TUM_GUN')
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    (ogr.adim % 2 == 0)
                                                        ? Colors.green.shade700
                                                        : Colors.blue.shade700,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 3),
                                                minimumSize: const Size(55, 26),
                                              ),
                                              onPressed: islemYapiliyor
                                                  ? null
                                                  : () =>
                                                      adimiIlerlet(ogr, plaka),
                                              child: Text(
                                                _siradakiButonMetni(ogr.adim),
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )
                                          else if (ogr.adim >= 4)
                                            const Text(
                                              'TAMAM',
                                              style: TextStyle(
                                                color: Colors.teal,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.event_busy_rounded,
                                              size: 17,
                                              color: ogr.izinli.isNotEmpty
                                                  ? Colors.deepPurple
                                                  : Colors.blueGrey,
                                            ),
                                            tooltip: 'İzinli İşaretle',
                                            onPressed: islemYapiliyor
                                                ? null
                                                : () => izinliPenceresiAc(
                                                    ogr, plaka),
                                          ),
                                          if (ogr.adim > 0)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.undo_rounded,
                                                size: 16,
                                                color: Colors.grey,
                                              ),
                                              tooltip: 'Sıfırla',
                                              onPressed: islemYapiliyor
                                                  ? null
                                                  : () =>
                                                      adimiSifirla(ogr, plaka),
                                            ),
                                        ],
                                        IconButton(
                                          icon: const Icon(Icons.phone,
                                              color: Colors.teal, size: 18),
                                          tooltip: 'Ara',
                                          onPressed: () => akilliAramaPenceresi(
                                            context,
                                            ogr.adSoyad,
                                            ogr.veliTel,
                                            ogr.ogrenciTel,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                arslanogluGroupFooter(),
              ],
            ),
    );
  }

  Widget _sayacKutusu(String baslik, int sayi, Color renk) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: renk.withAlpha(26),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: renk.withAlpha(77)),
        ),
        child: Column(
          children: [
            Text(
              '$sayi',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: renk,
              ),
            ),
            Text(
              baslik,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: renk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ServisQrTarayiciEkrani extends StatefulWidget {
  final bool sabahMi;
  final String beklenenPlaka;
  final List<ServisHatti> tumServisler;

  const ServisQrTarayiciEkrani({
    super.key,
    required this.sabahMi,
    required this.beklenenPlaka,
    required this.tumServisler,
  });

  @override
  State<ServisQrTarayiciEkrani> createState() => _ServisQrTarayiciEkraniState();
}

class _ServisQrTarayiciEkraniState extends State<ServisQrTarayiciEkrani> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _tamamlandi = false;
  bool _flasAcik = false;
  String? _uyariMesaji;
  ServisHatti? _farkliServis;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _qrAlgilandi(BarcodeCapture capture) {
    if (_tamamlandi) return;
    final beklenenNorm = normalizePlaka(widget.beklenenPlaka);

    for (final barcode in capture.barcodes) {
      final ham = (barcode.rawValue ?? '').trim();
      if (ham.isEmpty) continue;

      final temiz = normalizePlaka(
        ham.replaceFirst(RegExp(r'^BALSUYU_SERVIS_', caseSensitive: false), ''),
      );

      if (temiz == beklenenNorm) {
        _tamamlandi = true;
        Navigator.pop(context, {
          'onay': true,
          'qr': true,
          'plaka': widget.beklenenPlaka,
        });
        return;
      }

      final eslesenler = widget.tumServisler
          .where((s) => normalizePlaka(s.plaka) == temiz)
          .toList();
      if (eslesenler.isNotEmpty) {
        final bulunan = eslesenler.first;
        if (_farkliServis?.plaka != bulunan.plaka) {
          setState(() {
            _farkliServis = bulunan;
            _uyariMesaji =
                'Farklı servis okutuldu: ${bulunan.plaka} (Beklenen: ${widget.beklenenPlaka})';
          });
        }
        return;
      }

      setState(() {
        _farkliServis = null;
        _uyariMesaji =
            'Geçersiz QR kod okutuldu. Lütfen servis camındaki veya şoför ekranındaki QR kodu okutunuz.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E26),
        foregroundColor: Colors.white,
        title: Text(
          widget.sabahMi
              ? 'Sabah QR Tarama (${widget.beklenenPlaka})'
              : 'Akşam QR Tarama (${widget.beklenenPlaka})',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _flasAcik ? Icons.flash_on : Icons.flash_off,
              color: Colors.amberAccent,
            ),
            tooltip: 'Flaş',
            onPressed: () async {
              try {
                await _controller.toggleTorch();
                if (mounted) setState(() => _flasAcik = !_flasAcik);
              } catch (_) {}
            },
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded,
                color: Colors.tealAccent),
            tooltip: 'Kamerayı Değiştir',
            onPressed: () async {
              try {
                await _controller.switchCamera();
              } catch (_) {}
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _qrAlgilandi,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_rounded,
                          color: Colors.redAccent, size: 52),
                      const SizedBox(height: 12),
                      const Text(
                        'Kamera Açılamadı',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lütfen tarayıcı/uygulama kamera iznine "İzin Ver" deyiniz.\n'
                        'iPhone kullanıyorsanız linki WhatsApp içinden değil doğrudan Safari\'den (https://) açınız.\n'
                        '(${error.errorCode.name})',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.tealAccent, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(180),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.tealAccent.withAlpha(120)),
              ),
              child: Text(
                'Beklenen Servis: ${widget.beklenenPlaka}\nServis QR kodunu yeşil çerçevenin içine tutunuz.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_uyariMesaji != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (_farkliServis != null
                              ? Colors.amber.shade900
                              : Colors.red.shade900)
                          .withAlpha(220),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _uyariMesaji!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_farkliServis != null) ...[
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.check_circle, size: 16),
                            label: Text(
                              '${_farkliServis!.plaka} Servisini Onayla',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              _tamamlandi = true;
                              Navigator.pop(context, {
                                'onay': true,
                                'qr': true,
                                'servis': _farkliServis,
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.black.withAlpha(180),
                    foregroundColor: Colors.amberAccent,
                    side: const BorderSide(color: Colors.amberAccent),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  icon: const Icon(Icons.touch_app_rounded, size: 18),
                  label: const Text(
                    'Kamera Okumuyor — Manuel Onayla',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () {
                    _tamamlandi = true;
                    Navigator.pop(context, {
                      'onay': true,
                      'qr': false,
                      'plaka': widget.beklenenPlaka,
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget mebLogoRozeti() {
  return Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFE30A17),
      border: Border.all(color: Colors.white, width: 1.2),
    ),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.local_fire_department_rounded,
            color: Colors.white, size: 13),
        Text(
          'MEB',
          style: TextStyle(
            color: Colors.white,
            fontSize: 7,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}

Widget arslanogluGroupFooter() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF111418),
      border: Border(
        top: BorderSide(color: const Color(0xFFD4AF37).withAlpha(128)),
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
            color: Colors.black,
          ),
          child: const Center(
            child: Icon(Icons.shield, color: Color(0xFFD4AF37), size: 13),
          ),
        ),
        const SizedBox(width: 8),
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ARSLANOĞLU',
              style: TextStyle(
                color: Color(0xFFD4AF37),
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 2.0,
              ),
            ),
            Text(
              'G R O U P',
              style: TextStyle(
                color: Color(0xFFE5C158),
                fontWeight: FontWeight.bold,
                fontSize: 6.5,
                letterSpacing: 3.5,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Container(height: 14, width: 1, color: Colors.white24),
        const SizedBox(width: 12),
        Text(
          'Yazılım & Servis Teknolojileri',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
        ),
      ],
    ),
  );
}
